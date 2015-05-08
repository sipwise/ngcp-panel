package NGCP::Panel::Utils::ProfilePackages;
use strict;
use warnings;

#use Sipwise::Base;
#use DBIx::Class::Exception;

use constant INITIAL_PROFILE_DISCRIMINATOR => 'initial';
use constant UNDERRUN_PROFILE_DISCRIMINATOR => 'underrun';
use constant TOPUP_PROFILE_DISCRIMINATOR => 'topup';

use constant _DISCRIMINATOR_MAP => { initial_profiles => INITIAL_PROFILE_DISCRIMINATOR,
                                     underrun_profiles => UNDERRUN_PROFILE_DISCRIMINATOR,
                                     topup_profiles => TOPUP_PROFILE_DISCRIMINATOR};

use constant _CARRY_OVER_TIMELY => 'carry_over_timely';

#use constant _INTERVAL_RELATION => { day => 1,
#                                     week => 7,
#                                     month => 28};

sub check_balance_interval {
    my (%params) = @_;
    my ($c,$resource,$err_code) = @params{qw/c resource err_code/};
    
    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    unless(defined $resource->{balance_interval_unit} && defined $resource->{balance_interval_value}){
        return 0 unless &{$err_code}("Balance interval definition required.",'balance_interval');
    }
    return 1;
}

sub check_carry_over_mode {
    my (%params) = @_;
    my ($c,$resource,$err_code) = @params{qw/c resource err_code/};
    
    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    if (defined $resource->{carry_over_mode} && $resource->{carry_over_mode} eq _CARRY_OVER_TIMELY) {
        unless(defined $resource->{timely_duration_unit} && defined $resource->{timely_duration_value}){
            return 0 unless &{$err_code}("'timely' interval definition required.",'timely_duration');
        }
    }
    return 1;
}

sub check_underrun_lock_level {
    my (%params) = @_;
    my ($c,$resource,$err_code) = @params{qw/c resource err_code/};
    
    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    if (defined $resource->{underrun_lock_level}) {
        unless(defined $resource->{underrun_lock_threshold}){
            return 0 unless &{$err_code}("If specifying an underun lock level, 'underrun_lock_threshold' is required.",'underrun_lock_threshold');
        }
    }
    return 1;
}

sub check_profiles {
    my (%params) = @_;
    my ($c,$resource,$mappings_to_create,$err_code) = @params{qw/c resource mappings_to_create err_code/};
    
    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    my $mappings_counts = {};
    return 0 unless prepare_package_profile_set(c => $c, resource => $resource, field => 'initial_profiles', mappings_to_create => $mappings_to_create, mappings_counts => $mappings_counts, err_code => $err_code);
    if ($mappings_counts->{count_any_network} < 1) {
        return 0 unless &{$err_code}("An initial billing profile mapping with no billing network is required.",'initial_profiles');
    }    
    $mappings_counts = {};
    return 0 unless prepare_package_profile_set(c => $c, resource => $resource, field => 'underrun_profiles', mappings_to_create => $mappings_to_create, mappings_counts => $mappings_counts, err_code => $err_code);
    if ($mappings_counts->{count} > 0 && ! defined $resource->{underrun_profile_threshold}) {
        return 0 unless &{$err_code}("If specifying underung profile mappings, 'underrun_profile_threshold' is required.",'underrun_profile_threshold');
    }
    $mappings_counts = {};
    return 0 unless prepare_package_profile_set(c => $c, resource => $resource, field => 'topup_profiles', mappings_to_create => $mappings_to_create, mappings_counts => $mappings_counts, err_code => $err_code);

    return 1;
}

sub prepare_profile_package {
    my (%params) = @_;
    
    my ($c,$resource,$mappings_to_create,$err_code) = @params{qw/c resource mappings_to_create err_code/};    

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    #if (defined $resource->{reseller_id}) {
    #    my $reseller = $schema->resultset('resellers')->find($resource->{reseller_id});
    #    unless($reseller) {
    #        return 0 unless &{$err_code}("Invalid 'reseller_id' ($resource->{reseller_id}).");
    #    }
    #}
    
    return 0 unless check_carry_over_mode(c => $c, resource => $resource, err_code => $err_code);
    return 0 unless check_underrun_lock_level(c => $c, resource => $resource, err_code => $err_code);
    
    return 0 unless check_profiles(c => $c, resource => $resource, mappings_to_create => $mappings_to_create, err_code => $err_code);
    
    return 1;
}  

sub prepare_package_profile_set {
    my (%params) = @_;
    #my ($schema,$resource,$field,$mappings_to_create,$mappings_counts,$err_code) = @_;
    
    my ($c,$resource,$field,$mappings_to_create,$mappings_counts,$err_code) = @params{qw/c resource field mappings_to_create mappings_counts err_code/};    

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }
    
    my $reseller_id = $resource->{reseller_id};

    #if (! exists $resource->{$field} ) {
    #    $resource->{$field} = [];
    #}
    $resource->{$field} //= [];
    
    if (ref $resource->{$field} ne 'ARRAY') {
        return 0 unless &{$err_code}("Invalid field '$field'. Must be an array.",$field);
    }
    
    if (defined $mappings_counts) {
        $mappings_counts->{count} //= 0;
        $mappings_counts->{count_any_network} //= 0;
    }
    
    my $prepaid = 0;
    my $mappings = delete $resource->{$field};
    foreach my $mapping (@$mappings) {
        if (ref $mapping ne 'HASH') {
            return 0 unless &{$err_code}("Invalid element in array '$field'. Must be an object.",$field);
        }
        if (defined $mappings_to_create) {
            my $profile = $schema->resultset('billing_profiles')->find($mapping->{profile_id});
            unless($profile) {
                return 0 unless &{$err_code}("Invalid 'profile_id' ($mapping->{profile_id}).",$field);
            }
            if ($profile->status eq 'terminated') {
                return 0 unless &{$err_code}("Invalid 'profile_id' ($mapping->{profile_id}), already terminated.",$field);
            }            
            if (defined $reseller_id && defined $profile->reseller_id && $reseller_id != $profile->reseller_id) { #($profile->reseller_id // -1)) {
                return 0 unless &{$err_code}("The reseller of the profile package doesn't match the reseller of the billing profile (" . $profile->name . ").",$field);
            }
            if (defined $prepaid) {
                if ($profile->prepaid != $prepaid) {
                    return 0 unless &{$err_code}("Switching between prepaid and post-paid billing profiles is not supported (" . $profile->name . ").",$field);
                }
            } else {
                $prepaid = $profile->prepaid;
            }
            my $network;
            if (defined $mapping->{network_id}) {
                $network = $schema->resultset('billing_networks')->find($mapping->{network_id});
                unless($network) {
                    return 0 unless &{$err_code}("Invalid 'network_id'.",$field);
                }
                if (defined $reseller_id && defined $network->reseller_id && $reseller_id != $network->reseller_id) { #($network->reseller_id // -1)) {
                    return 0 unless &{$err_code}("The reseller of the profile package doesn't match the reseller of the billing network (" . $network->name . ").",$field);
                }
            }
            push(@$mappings_to_create,{
                profile_id => $profile->id,
                network_id => (defined $network ? $network->id : undef),
                discriminator => field_to_discriminator($field),
            });
        }
        if (defined $mappings_counts) {
            $mappings_counts->{count} += 1;
            $mappings_counts->{count_any_network} += 1 unless $mapping->{network_id};
        }
    }   
    return 1;
}

sub field_to_discriminator {
    my ($field) = @_;
    return _DISCRIMINATOR_MAP->{$field};
}

sub get_contract_count_stmt {
    return "select count(distinct c.id) from `billing`.`contracts` c where c.`profile_package_id` = `me`.`id` and c.status != 'terminated'";
}

sub _get_profile_set_group_stmt {
    my ($discriminator) = @_;
    my $grp_stmt = "group_concat(if(bn.`name` is null,bp.`name`,concat(bp.`name`,'/',bn.`name`)) separator ', ')";
    my $grp_len = 30;
    return "select if(length(".$grp_stmt.") > ".$grp_len.", concat(left(".$grp_stmt.", ".$grp_len."), '...'), ".$grp_stmt.") from `billing`.`package_profile_sets` pps join `billing`.`billing_profiles` bp on bp.`id` = pps.`profile_id` left join `billing`.`billing_networks` bn on bn.`id` = pps.`network_id` where pps.`package_id` = `me`.`id` and pps.`discriminator` = '" . $discriminator . "'";
}

sub get_datatable_cols {
    
    my ($c) = @_;
    return (
        { name => "contract_cnt", "search" => 0, "title" => $c->loc("Used (contracts)"), },
        { name => 'initial_profiles_grp', accessor => "initial_profiles_grp", search => 0, title => $c->loc('Initial Profiles'),
         literal_sql => _get_profile_set_group_stmt(INITIAL_PROFILE_DISCRIMINATOR) },
        { name => 'underrun_profiles_grp', accessor => "underrun_profiles_grp", search => 0, title => $c->loc('Underrun Profiles'),
         literal_sql => _get_profile_set_group_stmt(UNDERRUN_PROFILE_DISCRIMINATOR) },
        { name => 'topup_profiles_grp', accessor => "topup_profiles_grp", search => 0, title => $c->loc('Top-up Profiles'),
         literal_sql => _get_profile_set_group_stmt(TOPUP_PROFILE_DISCRIMINATOR) },
        
        { name => 'profile_name', accessor => "profiles_srch", search => 1, join => { profiles => 'billing_profile' },
          literal_sql => 'billing_profile.name' },
        { name => 'network_name', accessor => "network_srch", search => 1, join => { profiles => 'billing_network' },
          literal_sql => 'billing_network.name' },        
    );
    
}
        
1;