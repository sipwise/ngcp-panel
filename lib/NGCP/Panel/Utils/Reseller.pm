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
