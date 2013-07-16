package NGCP::Panel::Utils::Subscriber;
use strict;
use warnings;

use Sipwise::Base;
use DBIx::Class::Exception;

sub get_usr_preference_rs {
    my %params = @_;

    my $c = $params{c};
    my $attribute = $params{attribute};
    my $prov_subscriber= $params{prov_subscriber};

    my $preference = $c->model('DB')->resultset('voip_preferences')->find({
            attribute => $attribute, 'usr_pref' => 1,
        })->voip_usr_preferences->search_rs({
            subscriber_id => $prov_subscriber->id,
        });
    return $preference;
}

1;

=head1 NAME

NGCP::Panel::Utils::Subscriber

=head1 DESCRIPTION

A temporary helper to manipulate subscriber data

=head1 METHODS

=head2 get_usr_preference_rs

Parameters:
    c               The controller
    prov_subscriber The provisioning_voip_subscriber row
    attribute       The name of the usr preference

Returns a result set for the voip_usr_preference of the given subscriber.

=head1 AUTHOR

Andreas Granig,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
