package NGCP::Panel::Utils::API::Validate;
use strict;
use warnings;
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

sub check_autoprov_device_id{
    my($mod, $c, $device_id, $process_extras) = @_;
    my $model_rs = $c->model('DB')->resultset('autoprov_devices')->search({ 
        id => $device_id 
    });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $model_rs = $model_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    my $model = $model_rs->first;
    unless($model) {
        $c->log->error("invalid device_id '$device_id'");
        $mod->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device model does not exist");
        return;
    }
    $process_extras->{model} = $model;
    return 1;
}
1;

=head1 NAME

NGCP::Panel::Utils::API::Subscribers

=head1 DESCRIPTION

A temporary helper to manipulate subscribers related data in REST API modules

=head1 METHODS

=head2 get_active_subscriber

Set of validate methods for different resources.

=head1 AUTHOR

Irina Peshinskaya

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
