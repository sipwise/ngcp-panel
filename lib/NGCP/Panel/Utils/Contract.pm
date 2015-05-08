package NGCP::Panel::Utils::Contract;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;
use NGCP::Panel::Utils::DateTime;
use DateTime::Format::Strptime qw();

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
    for my $subscriber($contract->voip_subscribers->all) {
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
    my $schema = $params{schema};
    my $dtf = $schema->storage->datetime_parser;
    my $rs = $schema->resultset('contracts')
        ->search({
            $params{include_terminated} ? () : ('me.status' => { '!=' => 'terminated' }),
        },{
            bind => [ ( $dtf->format_datetime(NGCP::Panel::Utils::DateTime::current_local) ) x 2],
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
    my $c = $params{c};

    my $customers = get_contract_rs(
        schema => $c->model('DB'),
        include_terminated => $params{include_terminated},
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
        $allzones{$zname}{zone} = $zone->get_column('zone')//'';
        $allzones{$zname}{zone_detail} = $zone->get_column('zone_detail')//'';
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

sub prepare_billing_mappings {
    my (%params) = @_;

    my ($c,$resource,$old_resource,$mappings_to_create,$delete_mappings,$err_code) = @params{qw/c resource old_resource mappings_to_create delete_mappings err_code/};

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    #if (defined $resource->{billing_profile_id} && defined $resource->{billing_profiles}) {
    #    return 0 unless &{$err_code}("Either 'billing_profile_id' or 'billing_profiles' can be specified, not both.");
    #} elsif (!defined $resource->{billing_profile_id} && !defined $resource->{billing_profiles}) {
    #    return 0 unless &{$err_code}("Neither 'billing_profile_id' nor 'billing_profiles' specified.");
    #}
    
    my $profile_def_mode = $resource->{billing_profile_definition} // 'id';
    my $now = NGCP::Panel::Utils::DateTime::current_local;
            
    #$resource->{contact_id} //= undef;
    my $reseller_id = undef;
    my $is_customer = 1;
    if (defined $resource->{contact_id}) {
        my $contact = $schema->resultset('contacts')->find($resource->{contact_id});
        if ($contact) {
            $reseller_id = $contact->reseller_id; #($contact->reseller_id // -1);
            $is_customer = defined $reseller_id;
        }
    }

    my $product_id = undef; #any subsequent create will fail without product_id
    my $prepaid = undef;
    my $billing_profile_id = undef;
    if (defined $old_resource) {
        # TODO: what about changed product, do we allow it?
        my $billing_mapping = $schema->resultset('billing_mappings')->find($old_resource->{billing_mapping_id});
        $product_id = $billing_mapping->product->id;
        $prepaid = $billing_mapping->billing_profile->prepaid;
        $billing_profile_id = $billing_mapping->billing_profile->id;
        #my $billing_mapping;
        #if (exists $old_resource->{billing_mapping_id}) {
        #    $billing_mapping = $schema->resultset('billing_mappings')->find($old_resource->{billing_mapping_id});
        #} elsif (exists $old_resource->{billing_mapping}) {
        #    $billing_mapping = $old_resource->{billing_mapping};
        #}
        #if (defined $billing_mapping) {
        #    $product_id = $billing_mapping->product->id;
        #    $prepaid = $billing_mapping->billing_profile->prepaid;
        #    $billing_profile_id = $billing_mapping->billing_profile->id;
        #}
    } else {
        if (exists $resource->{type}) {
            my $product = $schema->resultset('products')->find({ class => $resource->{type} });
            if ($product) {
                $product_id = $product->id;
            }            
        } elsif (exists $resource->{product_id}) {
            $product_id = $resource->{product_id};
        }
    }
   
    if ('id' eq $profile_def_mode) {
        my $delete = undef;
        if (defined $old_resource) { #update
            if (defined $resource->{billing_profile_id}) {
                if ($billing_profile_id != $resource->{billing_profile_id}) {
                    #change profile:
                    $delete = 0; #1; #delete future mappings?
                    my $entities = {};
                    return 0 unless _check_profile_network(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                        resource => $resource,
                        profile_id_field => 'billing_profile_id',
                        );
                    my ($profile) = @$entities{qw/profile/};                    
                    push(@$mappings_to_create,{billing_profile_id => $profile->id,
                        network_id => undef,
                        product_id => $product_id,
                        start_date => $now,
                        end_date => undef,
                    });                    
                } else {
                    #not changed, don't touch mappings
                    $delete = 0;
                }
            } else {
                #undef profile means not changed, don't touch mappings
                #undef profile is not allowed
                $delete = 0;
                my $entities = {};
                return 0 unless _check_profile_network(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                    resource => $resource,
                    profile_id_field => 'billing_profile_id',
                    );
            }
        } else { #create
            $delete = 1; #for the sake of completeness
            my $entities = {};
            return 0 unless _check_profile_network(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                resource => $resource,
                profile_id_field => 'billing_profile_id',
                );
            my ($profile) = @$entities{qw/profile/};
            push(@$mappings_to_create,{billing_profile_id => $profile->id,
                network_id => undef,
                product_id => $product_id,
                #we don't change the former behaviour in update situations:
                start_date => undef,
                end_date => undef,
            });
        }
        if (defined $delete_mappings && ref $delete_mappings eq 'SCALAR') {
            $$delete_mappings = $delete;
        }
        delete $resource->{profile_package_id};
    } elsif ('profiles' eq $profile_def_mode) {
        if (!defined $resource->{billing_profiles}) {
            $resource->{billing_profiles} //= [];
        }
        if (ref $resource->{billing_profiles} ne "ARRAY") {
            return 0 unless &{$err_code}("Invalid field 'billing_profiles'. Must be an array.");
        }
        #delete $resource->{billing_profile_id};
        #my $mappings = delete $resource->{billing_profiles};
        #my %start_dupes = ();
        my %interval_type_counts = ( open => 0, open_any_network => 0, 'open end' => 0, 'open start' => 0, 'start-end' => 0 );
        my $dtf = $schema->storage->datetime_parser;
        foreach my $mapping (@{$resource->{billing_profiles}}) {
            if (ref $mapping ne "HASH") {
                return 0 unless &{$err_code}("Invalid element in array 'billing_profiles'. Must be an object.");
            }
            my $entities = {};
            return 0 unless _check_profile_network(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                resource => $mapping,
                profile_id_field => 'profile_id',
                network_id_field => 'network_id',
                );
            my ($profile,$network) = @$entities{qw/profile network/};            
            if (defined $prepaid) {
                if ($profile->prepaid != $prepaid) {
                    return 0 unless &{$err_code}("Switching between prepaid and post-paid billing profiles is not supported (" . $profile->name . ").");
                }
            } else {
                $prepaid = $profile->prepaid;
            }

            # TODO: what about changed product, do we allow it?
            #my $product_class = delete $mapping->{type};
            #unless( (defined $product_class ) && ($product_class eq "sipaccount" || $product_class eq "pbxaccount") ) {
            #    return 0 unless &{$err_code}("Mandatory 'type' parameter is empty or invalid, must be 'sipaccount' or 'pbxaccount'.");
            #}
            #my $product = $schema->resultset('products')->find({ class => $product_class });
            #unless($product) {
            #    return 0 unless &{$err_code}("Invalid 'type'.");
            #} else {
            #    # add product_id just for form check (not part of the actual contract item)
            #    # and remove it after the check
            #    $mapping->{product_id} = $product->id;
            #}

            my $start = (defined $mapping->{start} ? NGCP::Panel::Utils::DateTime::from_string($mapping->{start}) : undef);
            my $stop = (defined $mapping->{stop} ? NGCP::Panel::Utils::DateTime::from_string($mapping->{stop}) : undef);

            if (!defined $start && !defined $stop) { #open interval
                $interval_type_counts{open} += 1;
                $interval_type_counts{open_any_network} += 1 unless $network;
            } elsif (defined $start && !defined $stop) { #open end interval
                my $start_str = $dtf->format_datetime($start);
                if ($start <= $now) {
                    return 0 unless &{$err_code}("'start' timestamp ($start_str) is not in future.");
                }
                #if (exists $start_dupes{$start_str}) {
                #    $start_dupes{$start_str} += 1;
                #    return 0 unless &{$err_code}("Identical 'start' timestamps ($start_str) not allowed.");
                #} else {
                #    $start_dupes{$start_str} = 1;
                #}
                $interval_type_counts{'open end'} += 1;
            } elsif (!defined $start && defined $stop) { #open start interval
                my $stop_str = $dtf->format_datetime($stop);
                return 0 unless &{$err_code}("Interval with 'stop' timestamp ($stop_str) but no 'start' timestamp specified.");
                $interval_type_counts{'open start'} //= 0;
                $interval_type_counts{'open start'} += 1;                
            } else { #start-end interval
                my $start_str = $dtf->format_datetime($start);
                if ($start <= $now) {
                    return 0 unless &{$err_code}("'start' timestamp ($start_str) is not in future.");
                }
                my $stop_str = $dtf->format_datetime($stop);
                if ($start >= $stop) {
                    return 0 unless &{$err_code}("'start' timestamp ($start_str) has to be before 'stop' timestamp ($stop_str).");
                }
                #if (exists $start_dupes{$start_str}) {
                #    $start_dupes{$start_str} += 1;
                #    return 0 unless &{$err_code}("Identical 'start' timestamps ($start_str) not allowed.");
                #} else {
                #    $start_dupes{$start_str} = 1;
                #}
                $interval_type_counts{'start-end'} += 1;                                
            }

            push(@$mappings_to_create,{
                billing_profile_id => $profile->id,
                network_id => ($is_customer && defined $network ? $network->id : undef),
                product_id => $product_id,
                start_date => $start,
                end_date => $stop,
            });
        }
#        if (!defined $old_resource && $interval_type_counts{'open'} > 1) {
#            return 0 unless &{$err_code}("Only a single interval without 'start' and 'stop' timestamps is allowed.");
        if (!defined $old_resource && $interval_type_counts{'open_any_network'} < 1) {
            return 0 unless &{$err_code}("An interval without 'start' and 'stop' timestamps and no billing network is required.");            
        } elsif (defined $old_resource && $interval_type_counts{'open'} > 0) {
            return 0 unless &{$err_code}("Adding intervals without 'start' and 'stop' timestamps is not allowed.");
        }
        if (defined $delete_mappings && ref $delete_mappings eq 'SCALAR') {
            $$delete_mappings = 1; #always clear future mappings to place new ones
        }
        delete $resource->{profile_package_id};
    } elsif ('package' eq $profile_def_mode) {
        if (!$is_customer) {
            return 0 unless &{$err_code}("Setting a profile package is supported for customer contracts only.");
        }
        my $delete = undef;
        if (defined $old_resource) { #update
            if (defined $old_resource->{profile_package_id} && !defined $resource->{profile_package_id}) {
                #clear package: don't touch billing mappings (just clear profile package)
                $delete = 0;
            } elsif (!defined $old_resource->{profile_package_id} && defined $resource->{profile_package_id}) {
                #set package: apply initial mappings
                $delete = 0; #1; #delete future mappings?
                my $entities = {};
                return 0 unless _check_profile_package(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                    package_id => $resource->{profile_package_id},
                    );
                my ($package) = @$entities{qw/package/};
                foreach my $mapping ($package->initial_profiles->all) {
                    push(@$mappings_to_create,{ #assume not terminated, 
                        billing_profile_id => $mapping->profile_id,
                        network_id => ($is_customer ? $mapping->network_id : undef),
                        product_id => $product_id,
                        start_date => $now,
                        end_date => undef,
                    });
                }
            } elsif (defined $old_resource->{profile_package_id} && defined $resource->{profile_package_id}) {
                if ($old_resource->{profile_package_id} != $resource->{profile_package_id}) {
                    #change package: apply initial mappings
                    $delete = 0; #1; #delete future mappings?
                    my $entities = {};
                    return 0 unless _check_profile_package(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                        package_id => $resource->{profile_package_id},
                        );
                    my ($package) = @$entities{qw/package/};
                    foreach my $mapping ($package->initial_profiles->all) {
                        push(@$mappings_to_create,{ #assume not terminated, 
                            billing_profile_id => $mapping->profile_id,
                            network_id => ($is_customer ? $mapping->network_id : undef),
                            product_id => $product_id,
                            start_date => $now,
                            end_date => undef,
                        });
                    }
                } else {
                    #package unchanged: don't touch billing mappings
                    $delete = 0;
                }
            } else {
                #package unchanged (null): don't touch billing mappings
                $delete = 0;                
            }
        } else { #create
            $delete = 1; #for the sake of completeness
            my $entities = {};
            return 0 unless _check_profile_package(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                package_id => $resource->{profile_package_id},
                );
            my ($package) = @$entities{qw/package/};
            foreach my $mapping ($package->initial_profiles->all) {
                push(@$mappings_to_create,{ #assume not terminated, 
                    billing_profile_id => $mapping->profile_id,
                    network_id => ($is_customer ? $mapping->network_id : undef),
                    product_id => $product_id,
                    start_date => undef, #$now,
                    end_date => undef,
                });
            }
        }
        if (defined $delete_mappings && ref $delete_mappings eq 'SCALAR') {
            $$delete_mappings = $delete;
        }
    } else {
        return 0 unless &{$err_code}("Invalid 'billing_profile_definition'.");
    } 

    delete $resource->{billing_profile_id};
    delete $resource->{billing_profiles};
    
    delete $resource->{billing_profile_definition};
        
    return 1;
}
    
sub _check_profile_network {
    my (%params) = @_;
    my ($c,$res,$profile_id_field,$network_id_field,$reseller_id,$err_code,$entities) = @params{qw/c resource profile_id_field network_id_field reseller_id err_code entities/};    

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    unless(defined $res->{$profile_id_field}) {
        return 0 unless &{$err_code}("Invalid '$profile_id_field', not defined.");
    }    
    my $profile = $schema->resultset('billing_profiles')->find($res->{$profile_id_field});
    unless($profile) {
        return 0 unless &{$err_code}("Invalid '$profile_id_field' ($res->{$profile_id_field}).");
    }
    if ($profile->status eq 'terminated') {
        return 0 unless &{$err_code}("Invalid '$profile_id_field' ($res->{$profile_id_field}), already terminated.");
    }
    if (defined $reseller_id && defined $profile->reseller_id && $reseller_id != $profile->reseller_id) { #($profile->reseller_id // -1)) {
        return 0 unless &{$err_code}("The reseller of the contact doesn't match the reseller of the billing profile (" . $profile->name . ").");
    }
    my $network;
    if (defined $network_id_field && defined $res->{$network_id_field}) {
        $network = $schema->resultset('billing_networks')->find($res->{$network_id_field});
        unless($network) {
            return 0 unless &{$err_code}("Invalid '$network_id_field' ($res->{$network_id_field}).");
        }
        if (defined $reseller_id && defined $network->reseller_id && $reseller_id != $network->reseller_id) { #($network->reseller_id // -1)) {
            return 0 unless &{$err_code}("The reseller of the contact doesn't match the reseller of the billing network (" . $network->name . ").");
        }
    }
    if (defined $entities and ref $entities eq 'HASH') {
        $entities->{profile} = $profile;
        $entities->{network} = $network;
    }
    return 1;
}

sub _check_profile_package {
    my (%params) = @_;
    my ($c,$res,$package_id,$reseller_id,$err_code,$entities) = @params{qw/c resource package_id reseller_id err_code entities/};    

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    unless(defined $package_id) {
        return 0 unless &{$err_code}("Invalid 'profile_package_id', not defined.");
    }
    my $package = $schema->resultset('profile_packages')->find($package_id);
    unless($package) {
        return 0 unless &{$err_code}("Invalid 'profile_package_id'.");
    }
    if ($package->status eq 'terminated') {
        return 0 unless &{$err_code}("Invalid 'profile_package_id', already terminated.");
    }
    if (defined $reseller_id && defined $package->reseller_id && $reseller_id != $package->reseller_id) {
        return 0 unless &{$err_code}("The reseller of the contact doesn't match the reseller of the profile package (" . $package->name . ").");
    }
    
    if (defined $entities and ref $entities eq 'HASH') {
        $entities->{package} = $package;
    }
    return 1;
}

sub resource_from_future_mappings {
    my ($contract) = @_;
    return resource_from_mappings($contract,1);
}

sub resource_from_mappings {
    
    my ($contract,$future_only) = @_;
    
    my $is_customer = (defined $contract->contact->reseller_id ? 1 : 0);
    my @mappings_resource = ();
    
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    ); #validate_forms uses RFC3339 otherwise, which contains the tz offset part
    
    foreach my $mapping (billing_mappings_ordered($future_only ? future_billing_mappings($contract->billing_mappings) : $contract->billing_mappings)->all) {
        my %m = $mapping->get_inflated_columns;
        delete $m{id};
        $m{start} = delete $m{start_date};
        $m{stop} = delete $m{end_date};
        $m{start} = $datetime_fmt->format_datetime($m{start}) if defined $m{start};
        $m{stop} = $datetime_fmt->format_datetime($m{stop}) if defined $m{stop};
        $m{profile_id} = delete $m{billing_profile_id};
        delete $m{contract_id};
        delete $m{product_id};
        #if (!$is_customer && $m{network_id}) {
        #    die "bad";
        #}
        delete $m{network_id} unless $is_customer;
        push(@mappings_resource,\%m);
    }
    
    return \@mappings_resource;
    
}

sub billing_mappings_ordered {
    my ($rs) = @_;
    return $rs->search_rs(
        {},
        { order_by => { '-asc' => ['start_date', 'id']} },
    );    
}

sub remove_future_billing_mappings {
    
    my ($contract) = @_;
    
    future_billing_mappings($contract->billing_mappings)->delete;
    
}

sub future_billing_mappings {
    
    my ($rs) = @_;
    
    return $rs->search_rs({start_date => { '>' => NGCP::Panel::Utils::DateTime::current_local },});
    
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
