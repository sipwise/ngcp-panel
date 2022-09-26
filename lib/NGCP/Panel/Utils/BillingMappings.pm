package NGCP::Panel::Utils::BillingMappings;
use strict;
use warnings;

use Sipwise::Base;
use NGCP::Panel::Utils::DateTime qw();
use DateTime::Format::Strptime qw();

#my $_c_global;
#my $_commit = \&DBI::db::commit;
#*DBI::db::commit = sub {
#   $c->log->debug() if $c_global;
#   return $_commit(@_);
#}
#my $_rollback = \&DBI::db::rollback;
#*DBI::db::rollback = sub {
#   $c->log->debug() if $c_global;
#   return $_rollback(@_);
#}

sub append_billing_mappings {
    my %params = @_;
    my ($c,$schema,$contract,$now,$mappings_to_create,$delete_mappings) = @params{qw/c schema contract now mappings_to_create delete_mappings/};
    return unless $mappings_to_create;
    $schema //= $c->model('DB');
    my $dtf = $schema->storage->datetime_parser;
    my $mappings = '';
    foreach my $mapping (@$mappings_to_create) {
        $mappings .= (defined $mapping->{start_date} ? $dtf->format_datetime($mapping->{start_date}) : '') . ',';
        $mappings .= (defined $mapping->{end_date} ? $dtf->format_datetime($mapping->{end_date}) : '') . ',';
        $mappings .= (defined $mapping->{billing_profile_id} ? $mapping->{billing_profile_id} : '') . ',';
        $mappings .= (defined $mapping->{network_id} ? $mapping->{network_id} : '') . ',';
        $mappings .= ';'; #last = 1 by default
    }
    $c->log->debug('create contract id ' . $contract->id . " billing mappings via proc: $mappings") if $c;
    $c->model('DB')->txn_do(sub {
        $c->model('DB')->storage->dbh->do('call billing.schedule_contract_billing_profile_network(?,?,?)',undef,
            $contract->id,
            ((defined $now and $delete_mappings) ? $dtf->format_datetime($now) : undef),
            $mappings
        );
    });
    #$c->model('DB')->storage->dbh->do('call billing.schedule_contract_billing_profile_network(?,?,?)',undef,
    #    $contract->id,
    #    ((defined $now and $delete_mappings) ? $dtf->format_datetime($now) : undef),
    #    $mappings
    #);
    #my $contract_id = $contract->id;
    #$schema->storage->dbh_do(sub {
    #    my ($storage, $dbh, @args) = @_;
    #    local $dbh->{AutoCommit} = 0;
    #    $dbh->do('call billing.schedule_contract_billing_profile_network(?,?,?)',undef,
    #        $contract_id,
    #        ((defined $now and $delete_mappings) ? $dtf->format_datetime($now) : undef),
    #        $mappings
    #    );
    #});

}

sub get_actual_billing_mapping {
    my %params = @_;
    my ($c,$schema,$contract,$now) = @params{qw/c schema contract now/};
    $schema //= $c->model('DB');
    if ($now) {
        $c->log->debug('local timezone is ' . DateTime::TimeZone->new( name => 'local' )->name()) if $c;
        $now = NGCP::Panel::Utils::DateTime::set_local_tz($now);
    } else {
        $now = NGCP::Panel::Utils::DateTime::current_local;
    }
    my $contract_create = NGCP::Panel::Utils::DateTime::set_local_tz($contract->create_timestamp // $contract->modify_timestamp);
    #my $dtf = $schema->storage->datetime_parser;
    $now = $contract_create if $now < $contract_create; #if there is no mapping starting with or before $now, it would returns the mapping with max(id):

    #$start = NGCP::Panel::Utils::DateTime::convert_tz($start,$tz->name,'local',$c);
    my $effective_start_date = $schema->resultset('contracts_billing_profile_network_schedule')->search({
        'profile_network.contract_id' => $contract->id,
        effective_start_time => { '<=' => $now->epoch },
        'profile_network.base' => 1,
    },{
        join => 'profile_network',
    })->get_column('effective_start_time')->max;
    if (defined $effective_start_date) {
        my $bm = $schema->resultset('contracts_billing_profile_network_schedule')->search({
            contract_id => $contract->id,
            effective_start_time => $effective_start_date,
            base => 1,
        },{
            join => 'profile_network',
        })->first;
        $bm = $bm->profile_network if $bm;
        $c->log->debug("contract id " . $contract->id . " billing profile at $now (epoch = " . $now->epoch . ", tz = ".$now->time_zone.") is " .
            $bm->billing_profile->name . " (effective start date = $effective_start_date)") if $c;
        return $bm;
    } else {
        $c->log->error("no billing profile for contract id " . $contract->id . " at $now (" . $now->epoch . ")") if $c;
    }

}

sub get_actual_billing_mapping_stmt {
    my %params = @_;
    my ($c,$schema,$contract,$now,$projection,$contract_id_alias) = @params{qw/c schema contract now projection contract_id_alias/};
    $schema //= $c->model('DB');
    if ($now) {
        $now = NGCP::Panel::Utils::DateTime::set_local_tz($now);
    } else {
        $now = NGCP::Panel::Utils::DateTime::current_local;
    }
    $projection //= 'actual_billing_mapping.id';
    $contract_id_alias //= 'me.id';

    return sprintf(<<EOS
select
     %s
from (select
          contract_id,
          max(effective_start_time) as effective_start_date
     from billing.contracts_billing_profile_network_schedule cbpns join billing.contracts_billing_profile_network cbpn on cbpns.profile_network_id = cbpn.id
     where
          cbpns.effective_start_time <= %s
          and cbpn.base = 1
     group by cbpn.contract_id) as esd
join billing.contracts_billing_profile_network actual_billing_mapping on actual_billing_mapping.contract_id = esd.contract_id
join billing.contracts_billing_profile_network_schedule cbpns on cbpns.profile_network_id = actual_billing_mapping.id
join billing.billing_profiles billing_profile on actual_billing_mapping.billing_profile_id = billing_profile.id
left join billing.billing_networks billing_network on actual_billing_mapping.billing_network_id = billing_network.id
where esd.contract_id = %s and cbpns.effective_start_time = esd.effective_start_date and actual_billing_mapping.base = 1
EOS
    , $projection, $now->epoch, $contract_id_alias);

}

sub prepare_billing_mappings {
    my (%params) = @_;

    my ($c,
        $resource,
        $old_resource,
        $mappings_to_create,
        $now,
        $delete_mappings,
        $err_code,
        $billing_profile_field,
        $billing_profiles_field,
        $profile_package_field,
        $billing_profile_definition_field) = @params{qw/
        c
        resource
        old_resource
        mappings_to_create
        now
        delete_mappings
        err_code
        billing_profile_field
        billing_profiles_field
        profile_package_field
        billing_profile_definition_field
        /};

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    my $profile_def_mode = $resource->{billing_profile_definition} // 'id';
    $now //= NGCP::Panel::Utils::DateTime::current_local;

    my $reseller_id = undef;
    my $is_customer = 1;
    if (defined $resource->{contact_id}) {
        my $contact = $schema->resultset('contacts')->find($resource->{contact_id});
        if ($contact) {
            $reseller_id = $contact->reseller_id; #($contact->reseller_id // -1);
            $is_customer = defined $reseller_id;
        }
    }

#    my $product_id = undef; #any subsequent create will fail without product_id
    #my $prepaid = undef;
    my $billing_profile_id = undef;
    if (defined $old_resource) {
        # TODO: what about changed product, do we allow it?
        my $billing_mapping;
        if (exists $old_resource->{billing_mapping}) {
            $billing_mapping = $old_resource->{billing_mapping}; #$schema->resultset('billing_mappings')->find($old_resource->{billing_mapping_id});
        } elsif (exists $old_resource->{id}) {
            $billing_mapping = get_actual_billing_mapping(schema => $schema,
                contract => $schema->resultset('contracts')->find($old_resource->{id}),
                now => $now);
        #} else {
        #    return 0 unless &{$err_code}("No billing mapping or contract defined");
        }
#        $product_id = $billing_mapping->contract->product->id;
        #$prepaid = $billing_mapping->billing_profile->prepaid;
        $billing_profile_id = $billing_mapping->billing_profile->id;
#    } else {
#        if (exists $resource->{type} || exists $c->stash->{type}) {
#            my $productclass = (exists $c->stash->{type} ? $c->stash->{type} : $resource->{type});
#            my $product = $schema->resultset('products')->search_rs({ class => $productclass })->first;
#            if ($product) {
#                $product_id = $product->id;
#            }
#        } elsif (exists $resource->{product_id}) {
#            $product_id = $resource->{product_id};
#        }
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
                        field => $billing_profile_field,
                        );
                    my ($profile) = @$entities{qw/profile/};
                    push(@$mappings_to_create,{billing_profile_id => $profile->id,
                        network_id => undef,
#                        product_id => $product_id,
                        start_date => $now,
                        end_date => undef,
                    });
                } else {
                    #not changed, don't touch mappings
                    $delete = 0;
                }
            } else {
                #undef profile is not allowed
                $delete = 0;
                my $entities = {};
                return 0 unless _check_profile_network(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                    resource => $resource,
                    profile_id_field => 'billing_profile_id',
                    field => $billing_profile_field,
                    );
            }
        } else { #create
            $delete = 1; #for the sake of completeness
            my $entities = {};
            return 0 unless _check_profile_network(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                resource => $resource,
                profile_id_field => 'billing_profile_id',
                field => $billing_profile_field,
                );
            my ($profile) = @$entities{qw/profile/};
            push(@$mappings_to_create,{billing_profile_id => $profile->id,
                network_id => undef,
#                product_id => $product_id,
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
            return 0 unless &{$err_code}("Invalid field 'billing_profiles'. Must be an array.",$billing_profiles_field);
        }
        my %interval_type_counts = ( open => 0, open_any_network => 0, 'open end' => 0, 'open start' => 0, 'start-end' => 0 );
        my $dtf = $schema->storage->datetime_parser;
        foreach my $mapping (@{$resource->{billing_profiles}}) {
            if (ref $mapping ne "HASH") {
                return 0 unless &{$err_code}("Invalid element in array 'billing_profiles'. Must be an object.",$billing_profiles_field);
            }
            my $entities = {};
            return 0 unless _check_profile_network(c => $c, reseller_id => $reseller_id, err_code => $err_code, entities => $entities,
                resource => $mapping,
                field => $billing_profiles_field,
                profile_id_field => 'profile_id',
                network_id_field => 'network_id',
                );
            my ($profile,$network) = @$entities{qw/profile network/};
            #if (defined $prepaid) {
            #    if ($profile->prepaid != $prepaid) {
            #        return 0 unless &{$err_code}("Future switching between prepaid and post-paid billing profiles is not supported (" . $profile->name . ").",$billing_profiles_field);
            #    }
            #} else {
            #    $prepaid = $profile->prepaid;
            #}

            # TODO: what about changed product, do we allow it?
            #my $product_class = delete $mapping->{type};
            #unless( (defined $product_class ) && ($product_class eq "sipaccount" || $product_class eq "pbxaccount") ) {
            #    return 0 unless &{$err_code}("Mandatory 'type' parameter is empty or invalid, must be 'sipaccount' or 'pbxaccount'.");
            #}
            #my $product = $schema->resultset('products')->search_res({ class => $product_class })->first;
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
                    return 0 unless &{$err_code}("'start' timestamp ($start_str) is not in future.",$billing_profiles_field);
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
                return 0 unless &{$err_code}("Interval with 'stop' timestamp ($stop_str) but no 'start' timestamp specified.",$billing_profiles_field);
                $interval_type_counts{'open start'} //= 0;
                $interval_type_counts{'open start'} += 1;
            } else { #start-end interval
                my $start_str = $dtf->format_datetime($start);
                if ($start <= $now) {
                    return 0 unless &{$err_code}("'start' timestamp ($start_str) is not in future.",$billing_profiles_field);
                }
                my $stop_str = $dtf->format_datetime($stop);
                if ($start >= $stop) {
                    return 0 unless &{$err_code}("'start' timestamp ($start_str) has to be before 'stop' timestamp ($stop_str).",$billing_profiles_field);
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
#                product_id => $product_id,
                start_date => $start,
                end_date => $stop,
            });
        }

        if (!defined $old_resource && $interval_type_counts{'open_any_network'} < 1) {
            return 0 unless &{$err_code}("An initial interval without 'start' and 'stop' timestamps and no billing network is required.",$billing_profiles_field);
        } elsif (defined $old_resource && $interval_type_counts{'open'} > 0) {
            return 0 unless &{$err_code}("Adding intervals without 'start' and 'stop' timestamps is not allowed.",$billing_profiles_field);
        }
        if (defined $delete_mappings && ref $delete_mappings eq 'SCALAR') {
            $$delete_mappings = 1; #always clear future mappings to place new ones
        }
        delete $resource->{profile_package_id};
    } elsif ('package' eq $profile_def_mode) {
        if (!$is_customer) {
            return 0 unless &{$err_code}("Setting a profile package is supported for customer contracts only.",$billing_profile_definition_field);
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
                    field => $profile_package_field,
                    );
                my ($package) = @$entities{qw/package/};
                foreach my $mapping ($package->initial_profiles->all) {
                    push(@$mappings_to_create,{ #assume not terminated,
                        billing_profile_id => $mapping->profile_id,
                        network_id => ($is_customer ? $mapping->network_id : undef),
#                        product_id => $product_id,
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
                        field => $profile_package_field,
                        );
                    my ($package) = @$entities{qw/package/};
                    foreach my $mapping ($package->initial_profiles->all) {
                        push(@$mappings_to_create,{ #assume not terminated,
                            billing_profile_id => $mapping->profile_id,
                            network_id => ($is_customer ? $mapping->network_id : undef),
#                            product_id => $product_id,
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
                field => $profile_package_field,
                );
            my ($package) = @$entities{qw/package/};
            foreach my $mapping ($package->initial_profiles->all) {
                push(@$mappings_to_create,{ #assume not terminated,
                    billing_profile_id => $mapping->profile_id,
                    network_id => ($is_customer ? $mapping->network_id : undef),
#                    product_id => $product_id,
                    start_date => undef, #$now,
                    end_date => undef,
                });
            }
        }
        if (defined $delete_mappings && ref $delete_mappings eq 'SCALAR') {
            $$delete_mappings = $delete;
        }
    } else {
        return 0 unless &{$err_code}("Invalid 'billing_profile_definition'.",$billing_profile_definition_field);
    }

    delete $resource->{billing_profile_id};
    delete $resource->{billing_profiles};

    delete $resource->{billing_profile_definition};

    return 1;
}

sub check_prepaid_profiles_exist {
    my (%params) = @_;
    my ($c, $mappings_to_create) = @params{qw/c mappings_to_create/};

    my $schema = $c->model('DB');
    foreach my $billing_profile_info (@$mappings_to_create) {
        my $billing_profile = $schema->resultset('billing_profiles')->find($billing_profile_info->{billing_profile_id});
        if ($billing_profile && $billing_profile->prepaid) {
        #later we can put here all prepaid billing profiles in a array ref, if we will want to provide more informative error
            return $billing_profile_info->{billing_profile_id};
        }
    }
    return 0;
}

sub _check_profile_network {
    my (%params) = @_;
    my ($c,
        $res,
        $profile_id_field,
        $network_id_field,
        $field,
        $reseller_id,
        $err_code,
        $entities) = @params{qw/
        c
        resource
        profile_id_field
        network_id_field
        field
        reseller_id
        err_code entities
    /};

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    unless(defined $res->{$profile_id_field}) {
        return 0 unless &{$err_code}("Invalid '$profile_id_field', not defined.",$field);
    }
    my $profile = $schema->resultset('billing_profiles')->find($res->{$profile_id_field});
    unless($profile) {
        return 0 unless &{$err_code}("Invalid '$profile_id_field' ($res->{$profile_id_field}).",$field);
    }
    if ($profile->status eq 'terminated') {
        return 0 unless &{$err_code}("Invalid '$profile_id_field' ($res->{$profile_id_field}), already terminated.",$field);
    }
    if (defined $reseller_id && defined $profile->reseller_id && $reseller_id != $profile->reseller_id) { #($profile->reseller_id // -1)) {
        return 0 unless &{$err_code}("The reseller of the contact doesn't match the reseller of the billing profile (" . $profile->name . ").",$field);
    }
    my $network;
    if (defined $network_id_field && defined $res->{$network_id_field}) {
        $network = $schema->resultset('billing_networks')->find($res->{$network_id_field});
        unless($network) {
            return 0 unless &{$err_code}("Invalid '$network_id_field' ($res->{$network_id_field}).",$field);
        }
        if (defined $reseller_id && defined $network->reseller_id && $reseller_id != $network->reseller_id) { #($network->reseller_id // -1)) {
            return 0 unless &{$err_code}("The reseller of the contact doesn't match the reseller of the billing network (" . $network->name . ").",$field);
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
    my ($c,$res,$package_id,$reseller_id,$field,$err_code,$entities) = @params{qw/c resource package_id reseller_id field err_code entities/};

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    unless(defined $package_id) {
        return 0 unless &{$err_code}("Invalid 'profile_package_id', not defined.",$field);
    }
    my $package = $schema->resultset('profile_packages')->find($package_id);
    unless($package) {
        return 0 unless &{$err_code}("Invalid 'profile_package_id'.",$field);
    }

    if (defined $reseller_id && defined $package->reseller_id && $reseller_id != $package->reseller_id) {
        return 0 unless &{$err_code}("The reseller of the contact doesn't match the reseller of the profile package (" . $package->name . ").",$field);
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
        my $profile = $mapping->billing_profile;
        if ($profile and 'terminated' eq $profile->status) {
            next;
        }
        my $network = $mapping->network;
        if ($network and 'terminated' eq $network->status) {
            next;
        }
        my %m = $mapping->get_inflated_columns;
        delete $m{id};
        $m{start} = delete $m{start_date};
        $m{stop} = delete $m{end_date};
        $m{start} = $datetime_fmt->format_datetime($m{start}) if defined $m{start};
        $m{stop} = $datetime_fmt->format_datetime($m{stop}) if defined $m{stop};
        $m{effective_start_time} = $datetime_fmt->format_datetime(delete $m{effective_start_date});
        $m{profile_id} = delete $m{billing_profile_id};
        delete $m{contract_id};
        delete $m{product_id};
        delete $m{network_id} unless $is_customer;
        push(@mappings_resource,\%m);
    }

    return \@mappings_resource;

}

sub billing_mappings_ordered {
    my ($rs,$now,$actual_bm) = @_;

    my $dtf;
    $dtf = $rs->result_source->schema->storage->datetime_parser if defined $now;

    my @select = ();
    if ($now) {
        push(@select,{ '' => \[ 'if(`me`.`start_date` is null,0,`me`.`start_date` > ?)', $dtf->format_datetime($now) ], -as => 'is_future' });
    }
    if ($actual_bm) {
        #push(@select,{ '' => \[ '`me`.`id` = ?', $actual_bmid ], -as => 'is_actual' });
        push(@select,{ '' => \[ '`me`.`id` = ?', $actual_bm->id ], -as => 'is_actual' });
    }

    return $rs->search_rs(
        {},
        { order_by => { '-asc' => ['effective_start_date', 'id']},
          (scalar @select == 1 ? ('+select' => $select[0]) : ()),
          (scalar @select > 1 ? ('+select' => \@select) : ()),
        });

}

sub future_billing_mappings {

    my ($rs,$now) = @_;
    $now //= NGCP::Panel::Utils::DateTime::current_local;

    return $rs->search_rs({start_date => { '>' => $now },});

}

sub get_billingmappings_timeline_data {
    my ($c,$contract,$range,$stacked) = @_;
    unless ($range) {
        $range = eval { $c->req->body_data; };
        if ($@) {
            $c->log->error('error decoding timeline json request: ' . $@);
        }
    }
    my $start;
    $start = NGCP::Panel::Utils::DateTime::from_string($range->{start}) if $range->{start};
    my $end;
    $end = NGCP::Panel::Utils::DateTime::from_string($range->{end}) if $range->{end};
    $c->log->debug("timeline range $start - $end");
    #the max start date (of mappings with NULL end date) less than
    #the visible range end will become the range start:
    my $max_start_date = $contract->billing_mappings->search({  ## no critic (ProhibitCommaSeparatedStatements)
        ($end ? (start_date => [ -or =>
                { '<=' => $end },
                { '=' => undef },
            ]) : ()),
        end_date => { '=' => undef },
    },{
        order_by => { '-desc' => ['start_date', 'me.id']}, #NULL start dates at last
    })->first;
    #lower the range start, if required:
    if ($max_start_date) {
        if ($max_start_date->start_date) {
            $start = $max_start_date->start_date if (not $start or $max_start_date->start_date < $start);
        } else {
            $start = $max_start_date->start_date;
        }
    }
    my @timeline_events;
    #if ($stacked) {
        my $res = $contract->billing_mappings->search({  ## no critic (ProhibitCommaSeparatedStatements)
            ($end ? (start_date => ($start ? [ -and => {
                    '<=' => $end },{ #hide mappings beginning after range end
                    '>=' => $start   #and beginning before range start (max_start_date).
                },] : [ -or => {     #if there is a mapping with NULL start only,
                    '<=' => $end },{ #include all mapping beginning before range end.
                    '=' => undef
                },])) : ()),
        },{
            order_by => { '-asc' => ['start_date', 'me.id']},
            prefetch => [ 'billing_profile' , 'network' ]
        });
        @timeline_events = map {
            { $_->get_columns,
              billing_profile => { ($_->billing_profile ? ( name => $_->billing_profile->name, ) : ()) },
              network => { ($_->network ? ( name => $_->network->name, ) : ()) },
            };
        } $res->all;
    #} else {
    #    my $res = $c->model('DB')->resultset('contracts_billing_profile_network_schedule')->search({  ## no critic (ProhibitCommaSeparatedStatements)
    #        ($end ? (start_date => ($start ? [ -and => {
    #                '<=' => $end },{ #hide mappings beginning after range end
    #                '>=' => $start   #and beginning before range start (max_start_date).
    #            },] : [ -or => {     #if there is a mapping with NULL start only,
    #                '<=' => $end },{ #include all mapping beginning before range end.
    #                '=' => undef
    #            },])) : ()),
    #    },{
    #        join => { 'profile_network' => [ 'billing_profile', 'billing_network' ], },
    #        order_by => { '-asc' => ['effective_start_date', 'profile_network_id' ]},
    #        prefetch => [ 'billing_profile' , 'billing_network' ]
    #    });
    #    @timeline_events = map {
    #        { $_->get_columns,
    #          billing_profile => { ($_->billing_profile ? ( name => $_->billing_profile->name, ) : ()) },
    #          network => { ($_->network ? ( name => $_->network->name, ) : ()) },
    #        };
    #    } $res->all;
    #}
    return \@timeline_events;
}

1;
