package NGCP::Panel::Utils::Contract;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;

sub create_contract_balance {
    my %params = @_;

    my $c = $params{c};
    my $contract = $params{contract};
    my $profile = $params{profile};

    my ($cash_balance, $cash_balance_interval,
        $free_time_balance, $free_time_balance_interval) = (0,0,0,0);

    # first, calculate start and end time of current billing profile
    # (we assume billing interval of 1 month)
    my $stime = NGCP::Panel::Utils::DateTime::current_local->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1)->subtract(seconds => 1);

    # calculate free_time/cash ratio
    my $free_time = $profile->interval_free_time || 0;
    my $free_cash = $profile->interval_free_cash || 0;
    if($free_time or $free_cash) {
        $etime->add(seconds => 1);
        my $ctime = NGCP::Panel::Utils::DateTime::current_local->truncate(to => 'day');
        my $ratio = ($etime->epoch - $ctime->epoch) / ($etime->epoch - $stime->epoch);
        
        $cash_balance = sprintf("%.4f", $free_cash * $ratio);
        $cash_balance_interval = 0;

        $free_time_balance = sprintf("%.0f", $free_time * $ratio);
        $free_time_balance_interval = 0;
        $etime->subtract(seconds => 1);
    }

    try {
        my $schema = $c->model('DB');
        $schema->txn_do(sub {
            $schema->resultset('contract_balances')->create({
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
    return;
}

sub recursively_lock_contract {
    my %params = @_;

    my $c = $params{c};
    my $contract = $params{contract};
    my $status = $contract->status;
    if($status eq 'terminated') {
        $contract->autoprov_field_devices->delete_all;
    }

    # first, change all voip subscribers, in case there are any
    for my $subscriber($contract->voip_subscribers->all) {
        $subscriber->update({ status => $status });
        if($status eq 'terminated') {
            $subscriber->provisioning_voip_subscriber->delete
                if($subscriber->provisioning_voip_subscriber);
            $subscriber->voip_numbers->update_all({
                reseller_id => undef,
                subscriber_id => undef,
            });
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
    my $resellers = $c->model('DB')->resultset('resellers')->search({
        contract_id => $contract->id,
    });
    for my $reseller($resellers->all) {

        if($status eq 'terminated') {
            # remove domains in case of reseller termination
            for my $domain($reseller->domain_resellers->all) {
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
        for my $customer($customers->all) {
            $customer->update({ status => $status });
            for my $subscriber($customer->voip_subscribers->all) {
                $subscriber->update({ status => $status });
                if($status eq 'terminated') {
                    $subscriber->provisioning_voip_subscriber->delete
                        if($subscriber->provisioning_voip_subscriber);
                    $subscriber->voip_numbers->update_all({
                        reseller_id => undef,
                        subscriber_id => undef,
                    });
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
    my $schema = $params{schema};
    my $mapping_rs = $schema->resultset('billing_mappings');
    my $rs = $schema->resultset('contracts')
        ->search({
            'me.status' => { '!=' => 'terminated' },
            'billing_mappings.id' => {
                '=' => $mapping_rs->search({
                    contract_id => { -ident => 'me.id' },
                    start_date => [ -or =>
                        { '<=' => NGCP::Panel::Utils::DateTime::current_local },
                        { -is  => undef },
                    ],
                    end_date => [ -or =>
                        { '>=' => NGCP::Panel::Utils::DateTime::current_local },
                        { -is  => undef },
                    ],
                },{
                    alias => 'bilmap',
                    rows => 1,
                    order_by => {-desc => ['bilmap.start_date', 'bilmap.id']},
                })->get_column('id')->as_query,
            },
        },{
            'join' => 'billing_mappings',
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

sub get_contracts_rs_sippbx{
    my %params = @_;
    #pass here $c isn't very good idea, it doesn't allow "simple" call with really relevant information
    my $c = $params{c};
    # we only return customers, that is, contracts with contacts with a
    # reseller
    my $customers = get_contract_rs(
        schema => $c->model('DB'),
    );
    #really here we don't need role - we can pass only reseller_id, reseller_id should be tacken according to role in other method
    
    #for all
    $customers = $customers->search({
            'contact.reseller_id' => { '-not' => undef },
        },{
            join => 'contact',
    });

    my $reseller_condition;
    if($c->user->roles eq "reseller") {
        $reseller_condition = $c->user->reseller_id;
        $reseller_condition = $c->user->reseller_id;
    } elsif($c->user->roles eq "subscriberadmin") {
        $reseller_condition = $c->user->contract->contact->reseller_id;
    } elsif($c->user->roles eq "admin") {
    }
    if ($reseller_condition){
        $customers = $customers->search({
                'contact.reseller_id' => $reseller_condition ,
        });
    }
    
    $customers = $customers->search({
            '-or' => [
                'product.class' => 'sipaccount',
                'product.class' => 'pbxaccount',
            ],
        },{
            join => {'billing_mappings' => 'product' },
            '+select' => 'billing_mappings.id',
            '+as' => 'bmid',
    });
    
    return $customers;
}

sub get_contract_calls_rs{
    my %params = @_;
    (my ($c,$contract_id,$stime,$etime)) = @params{qw/c contract_id stime etime/};
    
#     SELECT 'out' as direction, SUM(c.source_customer_cost) AS cost, b.zone,
#                          COUNT(*) AS number, SUM(c.duration) AS duration
#                     FROM accounting.cdr c
#                     LEFT JOIN billing.voip_subscribers v ON c.source_user_id = v.uuid
#                     LEFT JOIN billing.billing_zones_history b ON b.id = c.source_customer_billing_zone_id
#                    WHERE v.contract_id = ?
#                      AND c.call_status = 'ok'
#                          $start_time $end_time
#                    GROUP BY b.zone 

    my $zonecalls_rs = $c->model('DB')->resultset('cdr')->search( {
#        source_user_id => { 'in' => [ map {$_->uuid} @{$contract->{subscriber}} ] },
        call_status       => 'ok',
        source_user_id    => { '!=' => '0' },
        source_account_id => $contract_id,
#         start_time        =>
#             [ -and =>
#                 { '>=' => $stime->epoch},
#                 { '<=' => $etime->epoch},
#             ],

#             {
#             '>=' => ["unix_timestamp(?)", $stime],
# '<=' => ["unix_timestamp(?)",$etime] },
#                { '>=' => \[ "unix_timestamp(?)", $stime ] },
#                { '<=' => \[ "unix_timestamp(?)", $etime ] },
#requires fix: 757           #$self->_assert_bindval_matches_bindtype(@sub_bind);
#in SQL::Abstract, 
 
    },{
        'select'   => [ 
            { sum         => 'me.source_customer_cost', -as => 'cost' },
            { sum         => 'me.source_customer_free_time', -as => 'free_time' },
            { sum         => 'me.duration', -as => 'duration' },
            { count       => '*', -as => 'number' },
            'source_customer_billing_zones_history.zone',
        ],
        'as' => [qw/cost free_time duration number zone/],
        join        => 'source_customer_billing_zones_history',
        group_by    => 'source_customer_billing_zones_history.zone',
    } );

    return $zonecalls_rs;
}

sub get_contract_zonesfees_rs {
    my %params = @_;
    my $c = $params{c};
    my $stime = $params{stime};
    my $etime = $params{etime};
    my $contract_id = $params{contract_id};
    my $subscriber_uuid = $params{subscriber_uuid};

    # should not be neccessary, done before
#    $stime ||= NGCP::Panel::Utils::DateTime::current_local()->truncate( to => 'month' );
#    $etime ||= $stime->clone->add( months => 1 );

#     SELECT 'out' as direction, SUM(c.source_customer_cost) AS cost, b.zone,
#                          COUNT(*) AS number, SUM(c.duration) AS duration
#                     FROM accounting.cdr c
#                     LEFT JOIN billing.voip_subscribers v ON c.source_user_id = v.uuid
#                     LEFT JOIN billing.billing_zones_history b ON b.id = c.source_customer_billing_zone_id
#                    WHERE v.contract_id = ?
#                      AND c.call_status = 'ok'
#                          $start_time $end_time
#                    GROUP BY b.zone

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
        ],
        'as' => [qw/customercost carriercost resellercost free_time duration number zone/],
        join        => 'source_customer_billing_zones_history',
        group_by    => 'source_customer_billing_zones_history.zone',
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
        ],
        'as' => [qw/customercost carriercost resellercost free_time duration number zone/],
        join        => 'destination_customer_billing_zones_history',
        group_by    => 'destination_customer_billing_zones_history.zone',
        order_by    => 'destination_customer_billing_zones_history.zone',
    } );

    return ($zonecalls_rs_in, $zonecalls_rs_out);
}


sub get_contract_zonesfees {
    my %params = @_;

    my ($zonecalls_rs_in, $zonecalls_rs_out) = get_contract_zonesfees_rs(%params);

    my %zones;
    for my $zone ($zonecalls_rs_in->all, $zonecalls_rs_out->all) {
        my $zname = $zone->get_column('zone') // '';

        my %cols = $zone->get_inflated_columns;
        $zones{$zname}{customercost} += $cols{customercost} || 0;
        $zones{$zname}{carriercost} += $cols{carriercost} || 0;
        $zones{$zname}{resellercost} += $cols{resellercost} || 0;
        $zones{$zname}{duration} += $cols{duration} || 0;
        $zones{$zname}{free_time} += $cols{free_time} || 0;
        $zones{$zname}{number} += $cols{number} || 0;

        delete $zones{$zname}{zone};
    }

    return \%zones;
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
