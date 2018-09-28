package NGCP::Panel::Utils::Reseller;
use strict;
use warnings;

use Sipwise::Base;

sub create_email_templates{
    my %params = @_;
    my($c, $reseller) = @params{qw/c reseller/};

    foreach ( $c->model('DB')->resultset('email_templates')->search_rs({ 'reseller_id' => undef })->all){
        my $email_template =  { $_->get_inflated_columns };
        delete $email_template->{id};
        $email_template->{reseller_id} = $reseller->id;
        $c->model('DB')->resultset('email_templates')->create($email_template);
    }
}

sub check_reseller_create_item {
    my ($c,$reseller_id,$err_code) = @_;
    #my ($c,$reseller_id,$err_code) = @params{qw/c reseller_id err_code/};

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ($c->user->roles eq "admin") {
        if (defined $reseller_id) {
            my $reseller = $schema->resultset('resellers')->find($reseller_id);
            unless ($reseller) {
                return 0 unless &{$err_code}("Invalid reseller ID.");
            }
        } else {
            #ok
        }
    } elsif($c->user->roles eq "reseller") {
        if (defined $reseller_id) {
            my $reseller = $schema->resultset('resellers')->find($reseller_id);
            unless ($reseller) {
                return 0 unless &{$err_code}("Invalid reseller ID.");
            } else {
                if ($c->user->reseller_id != $reseller->id) {
                    return 0 unless &{$err_code}("Reseller ID other than the user's reseller ID is not allowed.");
                }
            }
        } else {
            return 0 unless &{$err_code}("Undefined reseller ID not allowed.");
        }
    } else {
        return 0 unless &{$err_code}("Creating items associated with a reseller is allowed for admin and reseller users only.");
    }
    return 1;

}

sub check_reseller_update_item {
    my ($c,$new_reseller_id,$old_reseller_id,$err_code) = @_;
    #my ($c,$new_reseller_id,$old_reseller_id,$err_code) = @params{qw/c new_reseller_id old_reseller_id err_code/};

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ($c->user->roles eq "admin") {
        if (defined $new_reseller_id) {
            if (defined $old_reseller_id) {
                if ($new_reseller_id != $old_reseller_id) {
                    return 0 unless &{$err_code}("Changing the reseller ID is not allowed.");
                }
            } else {
                return 0 unless &{$err_code}("Cannot set a reseller ID if it was unset before.");
            }
        } else {
            if (defined $old_reseller_id) {
                #ok
            } else {
                #ok
            }
        }
    } elsif($c->user->roles eq "reseller") {
        if (defined $new_reseller_id) {
            if (defined $old_reseller_id) {
                if ($new_reseller_id != $old_reseller_id) {
                    return 0 unless &{$err_code}("Changing the reseller ID is not allowed.");
                }
            } else {
                return 0 unless &{$err_code}("Cannot set the reseller ID if it was unset before.");
            }
        } else {
            if (defined $old_reseller_id) {
                return 0 unless &{$err_code}("Changing the reseller ID is not allowed.");
            } else {
                return 0 unless &{$err_code}("Updating items not associated with a reseller is not allowed.");
            }
        }
    } else {
        return 0 unless &{$err_code}("Updating items associated with a reseller is allowed for admin and reseller users only.");
    }
    return 1;

}

sub check_reseller_delete_item {
    my ($c,$reseller_id,$err_code) = @_;
    #my ($c,$reseller_id,$err_code) = @params{qw/c reseller_id err_code/};

    my $schema = $c->model('DB');
    if (!defined $err_code || ref $err_code ne 'CODE') {
        $err_code = sub { return 0; };
    }

    if ($c->user->roles eq "admin") {
        #ok
    } elsif($c->user->roles eq "reseller") {
        if (defined $reseller_id) {
            if ($c->user->reseller_id != $reseller_id) {
                return 0 unless &{$err_code}("Deleting items with a reseller ID other than the user's reseller ID is not allowed.");
            }
        } else {
            return 0 unless &{$err_code}("Deleting items with undefined reseller ID not allowed.");
        }
    } else {
        return 0 unless &{$err_code}("Deleting items associated with a reseller is allowed for admin and reseller users only.");
    }
    return 1;

}
sub _handle_reseller_status_change {
    my ($c, $reseller) = @_;

    my $contract = $reseller->contract;
    $contract->update({ status => $reseller->status });
    NGCP::Panel::Utils::Contract::recursively_lock_contract(
        c => $c,
        contract => $contract,
    );

    if($reseller->status eq "terminated") {
        #delete ncos_levels
        $reseller->ncos_levels->delete_all;
        #delete voip_number_block_resellers
        $reseller->voip_number_block_resellers->delete_all;
        #delete voip_sound_sets
        $reseller->voip_sound_sets->delete_all;
        #delete voip_rewrite_rule_sets
        $reseller->voip_rewrite_rule_sets->delete_all;
        #delete autoprov_devices
        $reseller->autoprov_devices->delete_all;
        $reseller->email_templates->delete_all;
        $reseller->emergency_containers->search_related_rs('emergency_mappings')->delete_all;
        $reseller->emergency_containers->delete_all;
        $reseller->voip_intercepts->delete_all;
        $reseller->time_sets->delete_all;
    }
}

sub update_timesets {
    my %params = @_;
    my($c, $timeset, $resource, $form) = @params{qw/c timeset resource form/};

    $timeset->update({
            name => $resource->{name},
            reseller_id => $resource->{reseller_id},
        })->discard_changes;
    $timeset->time_periods->delete;
    for my $t ( @{ $form->values->{times} } ) { # not taking @{$resource->{times}}, to benefit from formhandler inflation
        $timeset->create_related("time_periods", {
                %{ $t },
            });
    }
}

sub create_timesets {
    my %params = @_;
    my($c, $resource) = @params{qw/c resource/};

    my $schema = $c->model('DB');

    my $timeset = $schema->resultset('voip_time_sets')->create({
        name => $resource->{name},
        reseller_id => $resource->{reseller_id},
    });
    for my $t ( @{$resource->{times}} ) {
        $timeset->create_related("time_periods", {
            %{ $t },
        });
    }
    return $timeset;
}

sub get_timeset {
    my %params = @_;
    my($c, $timeset) = @params{qw/c timeset/};

    my $resource = { $timeset->get_inflated_columns };

    my @periods;
    for my $period ($timeset->time_periods->all) {
        my $period_infl = { $period->get_inflated_columns, };
        delete @{ $period_infl }{'time_set_id', 'id'};
        for my $k (keys %{ $period_infl }) {
            delete $period_infl->{$k} unless defined $period_infl->{$k};
        }
        push @periods, $period_infl;
    }
    $resource->{times} = \@periods;
    return $resource;
}
1;

=head1 NAME

NGCP::Panel::Utils::Reseller

=head1 DESCRIPTION

A temporary helper to manipulate resellers data

=head1 METHODS

=head2 create_email_templates

Apply default email templates to newly created reseller

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
