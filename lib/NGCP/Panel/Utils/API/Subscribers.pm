package NGCP::Panel::Utils::API::Subscribers;
use strict;
use warnings;

use HTTP::Status qw(:constants);

sub get_active_subscriber{
    my($api, $c, $id, $params) = @_;

    my $sub_rs = $c->model('DB')->resultset('voip_subscribers')->search({
        'me.id' => $id,
        'me.status' => { '!=' => 'terminated' },
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $sub_rs = $sub_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { contract => 'contact' },
        });
    }
    my $sub = $sub_rs->first;
    unless($sub && $sub->provisioning_voip_subscriber) {
        $c->log->error($params->{error_log} ? $params->{error_log} : "invalid subscriber_id '$id'"); # TODO: user, message, trace, ...
        $api->error($c, HTTP_UNPROCESSABLE_ENTITY, $params->{error} ? $params->{error} : "No subscriber for subscriber_id found");
        return;
    }
    return $sub;
}
1;

=head1 NAME

NGCP::Panel::Utils::API::Subscribers

=head1 DESCRIPTION

A temporary helper to manipulate subscribers related data in REST API modules

=head1 METHODS

=head2 get_active_subscriber

Get subscriber NGCP::Schema::Result object of the active subscriber by the mandatory form parameter subscriber_id.

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
