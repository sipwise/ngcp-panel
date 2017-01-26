package NGCP::Panel::Utils::Contract;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;

sub get_contract_balance {
    my (%params) = @_;
    my $c = $params{c};
    my $contract = $params{contract};
    my $profile = $params{profile};
    my $stime = $params{stime};
    my $etime = $params{etime};
    my $schema = $params{schema} // $c->model('DB');

    my $balance = $contract->contract_balances
        ->find({
            start => { '>=' => $stime },
            end => { '<=' => $etime },
        });
    unless($balance) {
            $balance = create_contract_balance(
                c => $c,
                profile => $profile,
                contract => $contract,
                stime => $stime,
                etime => $etime,
                schema => $schema,
            );
    }
    return $balance;
}


sub create_contract_balance {
    my %params = @_;

    my $c = $params{c};
    my $contract = $params{contract};
    my $profile = $params{profile};
    my $schema = $params{schema} // $c->model('DB');


    # first, calculate start and end time of current billing profile
    # (we assume billing interval of 1 month)
    my $stime = $params{stime} || NGCP::Panel::Utils::DateTime::current_local->truncate(to => 'month');
    my $etime = $params{etime} || $stime->clone->add(months => 1)->subtract(seconds => 1);

    # calculate free_time/cash ratio
    my ($cash_balance, $cash_balance_interval,
        $free_time_balance, $free_time_balance_interval) = get_contract_balance_values(
        interval_free_time => ( $profile->interval_free_time || 0 ),
        interval_free_cash => ( $profile->interval_free_cash || 0 ),
        stime => $stime,
        etime => $etime,
    );

    my $balance;
    try {
        $schema->txn_do(sub {
            $balance = $schema->resultset('contract_balances')->create({
                contract_id => $contract->id,
                cash_balance => $cash_balance,
                cash_balance_interval => $cash_balance_interval,
                free_time_balance => $free_time_balance,
                free_time_balance_interval => $free_time_balance_interval,
                start => $stime,
                end => $etime,
            });
        });
    } catch($e) {
        if ($e =~ /Duplicate entry/) {
            $c->log->warn("Creating contract balance failed: Duplicate entry. Ignoring!");
        } else {
            $c->log->error("Creating contract balance failed: " . $e);
            $e->rethrow;
        }
    };
    return $balance;
}

sub get_contract_balance_values {
    my %params = @_;
    my($free_time, $free_cash, $stime, $etime) = @params{qw/interval_free_time interval_free_cash stime etime/};
    my ($cash_balance, $cash_balance_interval,
        $free_time_balance, $free_time_balance_interval) = (0,0,0,0);
    if($free_time or $free_cash) {
        $etime->add(seconds => 1);
        my $ctime = NGCP::Panel::Utils::DateTime::current_local->truncate(to => 'day');
        if( ( $ctime->epoch >= $stime->epoch ) && ( $ctime->epoch <= $etime->epoch ) ){
            my $ratio = ($etime->epoch - $ctime->epoch) / ($etime->epoch - $stime->epoch);
            
            $cash_balance = sprintf("%.4f", $free_cash * $ratio);
            $cash_balance_interval = 0;

            $free_time_balance = sprintf("%.0f", $free_time * $ratio);
            $free_time_balance_interval = 0;
        }
        $etime->subtract(seconds => 1);
    }
    return ($cash_balance, $cash_balance_interval, $free_time_balance, $free_time_balance_interval);
}

sub recursively_lock_contract {
    my %params = @_;

    my $c = $params{c};
    my $contract = $params{contract};
    my $schema = $params{schema} // $c->model('DB');
    my $status = $contract->status;
    if($status eq 'terminated') {
        $contract->autoprov_field_devices->delete_all;
    }

    # first, change all voip subscribers, in case there are any
    # we dont need to set to active, or any other level, already terminated subscribers
    for my $subscriber($contract->voip_subscribers->search_rs({ 'me.status' => { '!=' => 'terminated' } })->all) {
        $subscriber->update({ status => $status });
        if($status eq 'terminated') {
            NGCP::Panel::Utils::Subscriber::terminate(
                c => $c, subscriber => $subscriber,
            );
        } elsif($status eq 'locked') {
            NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                c => $c,
                prov_subscriber => $subscriber->provisioning_voip_subscriber,
                level => 4,
            ) if($subscriber->provisioning_voip_subscriber);
        } elsif($status eq 'active') {
            NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                c => $c,
                prov_subscriber => $subscriber->provisioning_voip_subscriber,
                level => 0,
            ) if($subscriber->provisioning_voip_subscriber);
        }
    }

    # then, check all child contracts in case of reseller
    my $resellers = $schema->resultset('resellers')->search({
        contract_id => $contract->id,
    });
    for my $reseller($resellers->all) {

        if($status eq 'terminated') {
            # remove domains in case of reseller termination
            for my $domain($reseller->domain_resellers->all) {
                my $prov_domain = $domain->domain->provisioning_voip_domain;
                if ($prov_domain) {
                    $prov_domain->voip_dbaliases->delete;
                    $prov_domain->voip_dom_preferences->delete;
                    $prov_domain->provisioning_voip_subscribers->delete;
                    $prov_domain->delete;
                }
                $domain->domain->delete;
                $domain->delete;
            }

            # remove admin logins in case of reseller termination
            for my $admin($reseller->admins->all) {
                if($admin->id == $c->user->id) {
                    die "Cannot delete the currently used account";
                }
                $admin->delete;
            }
        }

        # fetch sub-contracts of this contract
        my $customers = $c->model('DB')->resultset('contracts')->search({
                'contact.reseller_id' => $reseller->id,
            }, {
                join => 'contact',
            });
        my $data = { status => $status };
        $data->{terminate_timestamp} = NGCP::Panel::Utils::DateTime::current_local
            if($status eq 'terminated');
        for my $customer($customers->all) {
            $customer->update($data);
            for my $subscriber($customer->voip_subscribers->all) {
                $subscriber->update({ status => $status });
                if($status eq 'terminated') {
                    NGCP::Panel::Utils::Subscriber::terminate(
                        c => $c, subscriber => $subscriber,
                    );
                } elsif($status eq 'locked') {
                    NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                        c => $c,
                        prov_subscriber => $subscriber->provisioning_voip_subscriber,
                        level => 4,
                    ) if($subscriber->provisioning_voip_subscriber);
                } elsif($status eq 'active') {
                    NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                        c => $c,
                        prov_subscriber => $subscriber->provisioning_voip_subscriber,
                        level => 0,
                    ) if($subscriber->provisioning_voip_subscriber);
                }
            }
        }
    }
    return;
}

sub get_contract_rs {
    my %params = @_;
    my ($schema,$contract_id) = @params{qw/schema contract_id/};
    my $dtf = $schema->storage->datetime_parser;
    my $rs = $schema->resultset('contracts')
        ->search({
            $params{include_terminated} ? () : ('me.status' => { '!=' => 'terminated' }),
        },{
            bind => [ ( $dtf->format_datetime(NGCP::Panel::Utils::DateTime::current_local) ) x 2, ( $contract_id ) x 2],
            'join' => { 'billing_mappings_actual' => { 'billing_mappings' => 'product'}},
            '+select' => [
                'billing_mappings.id',
                'billing_mappings.start_date',
                'billing_mappings.product_id',
            ],
            '+as' => [
                'billing_mapping_id',
                'billing_mapping_start_date',
                'product_id',
            ],
            alias => 'me',
        });

    return $rs;
}

sub get_customer_rs {
    my %params = @_;
    my ($c,$contract_id) = @params{qw/c contract_id/};

    my $customers = get_contract_rs(
        schema => $c->model('DB'),
        include_terminated => $params{include_terminated},
        now => $now,
        contract_id => $contract_id,
    );
    
    $customers = $customers->search({
            'contact.reseller_id' => { '-not' => undef },
        },{
            join => 'contact',
    });

    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $customers = $customers->search({
                'contact.reseller_id' => $c->user->reseller_id,
        });
    } elsif($c->user->roles eq "subscriberadmin") {
        $customers = $customers->search({
                'contact.reseller_id' => $c->user->contract->contact->reseller_id,
        });
    } 
    
    $customers = $customers->search({
            '-or' => [
                'product.class' => 'sipaccount',
                'product.class' => 'pbxaccount',
            ],
        },{
            '+select' => 'billing_mappings.id',
            '+as' => 'bmid',
    });
    
    return $customers;
}

sub get_contract_zonesfees_rs {
    my %params = @_;
    my $c = $params{c};
    my $stime = $params{stime};
    my $etime = $params{etime};
    my $contract_id = $params{contract_id};
    my $subscriber_uuid = $params{subscriber_uuid};
    my $group_detail = $params{group_by_detail};

    my $zonecalls_rs_out = $c->model('DB')->resultset('cdr')->search( {
        'call_status'       => 'ok',
        'source_user_id'    => ($subscriber_uuid || { '!=' => '0' }),
        start_time        =>
            [ -and =>
                { '>=' => $stime->epoch},
                { '<=' => $etime->epoch},
            ],
        source_account_id => $contract_id,
    },{
        'select'   => [
            { sum         => 'me.source_customer_cost', -as => 'customercost' },
            { sum         => 'me.source_carrier_cost', -as => 'carriercost' },
            { sum         => 'me.source_reseller_cost', -as => 'resellercost' },
            { sum         => 'me.source_customer_free_time', -as => 'free_time' },
            { sum         => 'me.duration', -as => 'duration' },
            { count       => '*', -as => 'number' },
            'source_customer_billing_zones_history.zone',
            $group_detail ? 'source_customer_billing_zones_history.detail' : (),
        ],
        'as' => [
            qw/customercost carriercost resellercost free_time duration number zone/,
            $group_detail ? 'zone_detail' : (),
        ],
        join        => 'source_customer_billing_zones_history',
        group_by    => [
            'source_customer_billing_zones_history.zone', 
            $group_detail ? 'source_customer_billing_zones_history.detail' : (),
        ],
        order_by    => 'source_customer_billing_zones_history.zone',
    } );

    my $zonecalls_rs_in = $c->model('DB')->resultset('cdr')->search( {
        'call_status'       => 'ok',
        'destination_user_id'    => ($subscriber_uuid || { '!=' => '0' }),
        start_time        =>
            [ -and =>
                { '>=' => $stime->epoch},
                { '<=' => $etime->epoch},
            ],
        destination_account_id => $contract_id,
    },{
        'select'   => [
            { sum         => 'me.destination_customer_cost', -as => 'customercost' },
            { sum         => 'me.destination_carrier_cost', -as => 'carriercost' },
            { sum         => 'me.destination_reseller_cost', -as => 'resellercost' },
            { sum         => 'me.destination_customer_free_time', -as => 'free_time' },
            { sum         => 'me.duration', -as => 'duration' },
            { count       => '*', -as => 'number' },
            'destination_customer_billing_zones_history.zone',
            $group_detail ? 'destination_customer_billing_zones_history.detail' : (),
        ],
        'as' => [
            qw/customercost carriercost resellercost free_time duration number zone/,
            $group_detail ? 'zone_detail' : (),
        ],
        join        => 'destination_customer_billing_zones_history',
        group_by    => [
            'destination_customer_billing_zones_history.zone',
            $group_detail ? 'destination_customer_billing_zones_history.detail' : (),
        ],
        order_by    => 'destination_customer_billing_zones_history.zone',
    } );

    return ($zonecalls_rs_in, $zonecalls_rs_out);
}

sub get_contract_zonesfees {
    my %params = @_;

    my $c = $params{c};
    my $in = delete $params{in};
    my $out = delete $params{out};

    my ($zonecalls_rs_in, $zonecalls_rs_out) = get_contract_zonesfees_rs(%params);
    my @zones = (
        $in ? $zonecalls_rs_in->all : (),
        $out ? $zonecalls_rs_out->all : (),
    );
    
    my %allzones;
    for my $zone (@zones) {
        my $zname = $params{group_by_detail} ? 
            ($zone->get_column('zone')//'') . ' ' . ($zone->get_column('zone_detail')//'') :
            ($zone->get_column('zone')//'');

        my %cols = $zone->get_inflated_columns;
        if($c->user->roles eq "admin") {
            $allzones{$zname}{carriercost} += $cols{carriercost} || 0;
        }
        if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
            $allzones{$zname}{resellercost} += $cols{resellercost} || 0;
        }
        $allzones{$zname}{customercost} += $cols{customercost} || 0;
        $allzones{$zname}{duration} += $cols{duration} || 0;
        $allzones{$zname}{free_time} += $cols{free_time} || 0;
        $allzones{$zname}{number} += $cols{number} || 0;
        if($params{group_by_detail}){
            $allzones{$zname}{zone} = $zone->get_column('zone')//'';
            $allzones{$zname}{zone_detail} = $zone->get_column('zone_detail') // '';
        }
    }

    return \%allzones;
}

sub get_contract_calls_rs{
    my %params = @_;
    (my($c,$customer_contract_id,$stime,$etime)) = @params{qw/c customer_contract_id stime etime/};

    $stime ||= NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
    $etime ||= $stime->clone->add( months => 1 );

    my $calls_rs = $c->model('DB')->resultset('cdr')->search( {
#        source_user_id => { 'in' => [ map {$_->uuid} @{$contract->{subscriber}} ] },
        'call_status'       => 'ok',
        'source_user_id'    => { '!=' => '0' },
        'start_time'        => 
            [ -and =>
                { '>=' => $stime->epoch},
                { '<=' => $etime->epoch},
            ],
        'source_account_id' => $customer_contract_id,
    },{
        select => [qw/
            source_user source_domain source_cli 
            destination_user_in 
            start_time duration call_type
            source_customer_cost
            source_customer_billing_zones_history.zone
            source_customer_billing_zones_history.detail
        /],
        as => [qw/
            source_user source_domain source_cli 
            destination_user_in 
            start_time duration call_type
            source_customer_cost
            zone 
            zone_detail
        /],
        'join' => 'source_customer_billing_zones_history', 
        'order_by'    => 'start_time',
    } );    
 
    return $calls_rs;
}
1;

__END__

=head1 NAME

NGCP::Panel::Utils::Contract

=head1 DESCRIPTION

A temporary helper to manipulate Contract related data

=head1 METHODS

=head2 create_contract_balance

Parameters:
    c               The controller
    contract        The contract resultset
    profile         The billing_profile resultset

Creates a contract balance for the current month, if none exists yet
for this contract.

=head1 AUTHOR

Andreas Granig,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
