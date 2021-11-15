package NGCP::Panel::Utils::Contract;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::CallList qw();

sub recursively_lock_contract {
    my %params = @_;

    my $c = $params{c};
    my $contract = $params{contract};
    my $schema = $params{schema} // $c->model('DB');
    my $status = $contract->status;

    my $resellers = $schema->resultset('resellers')->search({
        contract_id => $contract->id,
    });

    if ($status eq 'terminated') {
        # check all child contracts in case of reseller
        for my $reseller ($resellers->all) {
            for my $admin ($reseller->admins->all) {
                if ($admin->id == $c->user->id) {
                    die "Cannot delete the currently used account";
                }
            }
        }
    }

    # first, change all voip subscribers, in case there are any
    # we don't need to set to active, or any other level, already terminated subscribers
    for my $subscriber ($contract->voip_subscribers->search_rs({
                        'me.status' => { '!=' => 'terminated' }
                        })->all) {
        if ($status ne 'locked' && $status eq $subscriber->status) {
            next;
        }
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

    if ($status eq 'terminated') {
        # remove contract associated pbx devices
        $contract->autoprov_field_devices->delete_all;
    }

    for my $reseller ($resellers->all) {

        # fetch sub-contracts of this contract
        my $customers = $c->model('DB')->resultset('contracts')->search({
                'contact.reseller_id' => $reseller->id,
            }, {
                join => 'contact',
            });
        my $data = { status => $status };
        if ($status eq 'terminated') {
            $data->{terminate_timestamp} = NGCP::Panel::Utils::DateTime::current_local
        }
        for my $customer ($customers->all) {
            $customer->update($data);
            for my $subscriber ($customer->voip_subscribers->all) {
                if ($status ne 'locked' && $status eq $subscriber->status) {
                    next;
                }
                $subscriber->update({ status => $status });
                if ($status eq 'terminated') {
                    NGCP::Panel::Utils::Subscriber::terminate(
                        c => $c, subscriber => $subscriber,
                    );
                } elsif ($status eq 'locked') {
                    NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                        c => $c,
                        prov_subscriber => $subscriber->provisioning_voip_subscriber,
                        level => 4,
                    ) if ($subscriber->provisioning_voip_subscriber);
                } elsif ($status eq 'active') {
                    NGCP::Panel::Utils::Subscriber::lock_provisoning_voip_subscriber(
                        c => $c,
                        prov_subscriber => $subscriber->provisioning_voip_subscriber,
                        level => 0,
                    ) if($subscriber->provisioning_voip_subscriber);
                }
            }
        }

        if ($status eq 'terminated') {
            # remove domains in case of reseller termination
            for my $domain ($reseller->domains->all) {
                my $prov_domain = $domain->provisioning_voip_domain;
                if ($prov_domain) {
                    $prov_domain->voip_dbaliases->delete;
                    $prov_domain->voip_dom_preferences->delete;
                    $prov_domain->provisioning_voip_subscribers->delete;
                    $prov_domain->delete;
                }
                $domain->delete;
            }

            # remove admin logins in case of reseller termination
            for my $admin($reseller->admins->all) {
                $admin->delete;
            }
        }
    }
    return;
}

sub get_contract_rs {
    my %params = @_;
    my ($c,$schema,$include_terminated) = @params{qw/c schema include_terminated/};
    $schema //= $c->model('DB');
    my $rs = $schema->resultset('contracts')->search({
        $include_terminated ? () : ('me.status' => { '!=' => 'terminated' }),  ## no critic (ProhibitCommaSeparatedStatements)
    }, undef);
    return $rs;
}

sub get_customer_rs {
    my %params = @_;
    my ($c,$schema,$include_terminated) = @params{qw/c schema include_terminated/};
    $schema //= $c->model('DB');
    my @product_ids = map { $_->id; } $schema->resultset('products')->search_rs({ 'class' => ['sipaccount','pbxaccount'] })->all;
    my $rs = get_contract_rs(
        c => $c,
        schema => $schema,
        include_terminated => $include_terminated,
    )->search_rs({
        'product_id' => { -in => [ @product_ids ] },
    },{
        join => 'contact',
    });

    if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
        $rs = $rs->search_rs({
            'contact.reseller_id' => { '-not' => undef },
        },undef);
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
        $rs = $rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },undef);
    } elsif($c->user->roles eq "subscriberadmin" or $c->user->roles eq "subscriber") {
        $rs = $rs->search({
            'contact.reseller_id' => $c->user->contract->contact->reseller_id,
        },undef);
    }

    return $rs;
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

    my @cols = ();
    push(@cols,qw/source_user source_domain source_cli destination_user_in/);
    #push(@cols,NGCP::Panel::Utils::CallList::get_suppression_id_colnames());
    push(@cols,qw/start_time duration call_type source_customer_cost/);
    my @colnames = @cols;
    push(@cols,qw/source_customer_billing_zones_history.zone source_customer_billing_zones_history.detail/);
    push(@colnames,qw/zone zone_detail/);

    my $calls_rs = $c->model('DB')->resultset('cdr')->search_rs({
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
        select => \@cols,
        as => \@colnames,
        'join' => 'source_customer_billing_zones_history',
        'order_by'    => 'start_time',
    });

    #suppression rs decoration at last, after any "select =>"
    return NGCP::Panel::Utils::CallList::call_list_suppressions_rs($c,$calls_rs,NGCP::Panel::Utils::CallList::SUPPRESS_INOUT);

}

sub is_peering_reseller_contract {
    my %params = @_;
    my($c, $contract) = @params{qw/c contract/};
    if ( defined $contract->product && is_peering_reseller_product(c => $c, product => $contract->product) ) {
        return 1;
    }
    return 0;
}

sub is_peering_reseller_product {
    my %params = @_;
    my($c, $product) = @params{qw/c product/};
    if (grep {$product->handle eq $_}
            ("SIP_PEERING", "PSTN_PEERING", "VOIP_RESELLER")) {
        return 1;
    }
    return 0;
}

sub acquire_contract_rowlocks {
    my %params = @_;
    my($c,$schema,$rs,$contract_id_field,$contract_ids,$contract_id) = @params{qw/c schema rs contract_id_field contract_ids contract_id/};

    $schema //= $c->model('DB');

    my %contract_id_map = ();
    my $rs_result = undef;
    if (defined $rs and defined $contract_id_field) {
        $rs_result = [ $rs->all ];
        foreach my $item (@$rs_result) {
            $contract_id_map{$item->$contract_id_field} = 1;
        }
    }
    if (defined $contract_ids) {
        foreach my $id (@$contract_ids) {
            $contract_id_map{$id} = 1;
        }
    }
    if (defined $contract_id) {
        $contract_id_map{$contract_id} = 1;
    }
    my @contract_ids_to_lock = keys %contract_id_map;
    my ($t1,$t2) = (time,undef);
    if (defined $contract_id && !defined $rs_result && !defined $contract_ids) {
        $c->log->debug('contract ID to be locked: ' . $contract_id) if $c;
        my $contract = $schema->resultset('contracts')->find({
                id => $contract_id
                },{for => 'update'});
        $t2 = time;
        $c->log->debug('contract ID ' . $contract_id . ' locked (' . ($t2 - $t1) . ' secs)') if $c;
        return $contract;
    } elsif ((scalar @contract_ids_to_lock) > 0) {
        @contract_ids_to_lock = sort { $a <=> $b } @contract_ids_to_lock; #"Access your tables and rows in a fixed order."
        my $contract_ids_label = join(', ',@contract_ids_to_lock);
        $c->log->debug('contract IDs to be locked: ' . $contract_ids_label) if $c;
        my @contracts = $schema->resultset('contracts')->search({
                id => { -in => [ @contract_ids_to_lock ] }
                },{for => 'update'})->all;
        $t2 = time;
        $c->log->debug('contract IDs ' . $contract_ids_label . ' locked (' . ($t2 - $t1) . ' secs)') if $c;
        if (defined $contract_ids || defined $contract_id) {
            return [ @contracts ];
        } else {
            return $rs_result;
        }
    }
    $c->log->debug('no contract IDs to be locked!') if $c;
    return [];
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
