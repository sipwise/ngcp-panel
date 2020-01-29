package NGCP::Panel::Utils::API::Calllist;
use strict;
use warnings;

use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::DateTime qw();

sub get_owner_data {
    my ($self, $c, $schema, $source, $optional_for_admin_reseller) = @_;

    my $ret;
    $source //= $c->req->params;
    my $src_subscriber_id = $source->{subscriber_id};
    my $src_customer_id = $source->{customer_id};

    $schema //= $c->model('DB');

    if($c->user->roles eq "admin" || $c->user->roles eq "reseller") {
        if($src_subscriber_id) {
            my $sub = $schema->resultset('voip_subscribers')->find($src_subscriber_id);
            unless($sub) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'subscriber_id'.");
                return;
            }
            if($c->user->roles eq "reseller" && $sub->contract->contact->reseller_id != $c->user->reseller_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'subscriber_id'.");
                return;
            }
            return {
                subscriber => $sub,
                customer => $sub->contract,
            };
        } elsif($src_customer_id) {
            my $cust = $schema->resultset('contracts')->find($src_customer_id);
            unless($cust && $cust->contact->reseller_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'customer_id'.");
                return;
            }
            if($c->user->roles eq "reseller" && $cust->contact->reseller_id != $c->user->reseller_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'customer_id'.");
                return;
            }
            return {
                subscriber => undef,
                customer => $cust,
            };
        } elsif (not $optional_for_admin_reseller) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Mandatory parameter 'subscriber_id' or 'customer_id' missing in request");
            return;
        }
    } elsif($c->user->roles eq "subscriberadmin") {
        if($src_subscriber_id) {
            my $sub = $schema->resultset('voip_subscribers')->find($src_subscriber_id);
            unless($sub) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'subscriber_id'.");
                return;
            }
            if($sub->contract_id != $c->user->account_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'subscriber_id'.");
                return;
            }
            return {
                subscriber => $sub,
                customer => $sub->contract,
            };
        } else {
            my $cust = $schema->resultset('contracts')->find($c->user->account_id);
            unless($cust && $cust->contact->reseller_id) {
                $self->error($c, HTTP_NOT_FOUND, "Invalid 'customer_id'.");
                return;
            }
            return {
                subscriber => undef,
                customer => $cust,
            };
        }
    } elsif($c->user->roles eq "subscriber") {
        return {
            subscriber => $c->user->voip_subscriber,
            customer => $c->user->voip_subscriber->contract,
        };
    } else {
        $self->error($c, HTTP_NOT_FOUND, "Unknown role '".$c->user->roles."' of the user.");
        return;
    }
}

sub apply_owner_timezone {
    my ($self,$c,$dt,$owner) = @_;
    my $result = $dt->clone;
    if($c->req->param('tz')) {
        if (DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
            # valid tz is checked in the controllers' GET already, but just in case
            # it passes through via POST or something, then just ignore wrong tz
            $result->set_time_zone($c->req->param('tz'));
        } else {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Query parameter 'tz' value is not a valid time zone");
            return;
        }
    } elsif ($owner and $c->req->param('use_owner_tz')) {
        my $tz;
        my $sub = $owner->{subscriber};
        my $cust = $owner->{customer};
        if ($owner->{subscriber}) {
            $tz = $c->model('DB')->resultset('voip_subscriber_timezone')->search_rs({
                subscriber_id => $owner->{subscriber}->id
            })->first;
        } elsif ($owner->{customer}) {
            $tz = $c->model('DB')->resultset('contract_timezone')->search_rs({
                contract_id => $owner->{customer}->id
            })->first;
        } else {
            # should not go here.
        }
        $result->set_time_zone(NGCP::Panel::Utils::DateTime::normalize_db_tz_name($tz->name)) if $tz;
    }
    return $result;
}

1;

=head1 NAME

NGCP::Panel::Utils::API::Calllist

=head1 DESCRIPTION

A temporary helper to manipulate calls related data in REST API modules

=head1 METHODS

=head2 get_owner_data

Check if mandatory calls list parameters customer_id or subscriber_id are presented and get proper objects.

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
