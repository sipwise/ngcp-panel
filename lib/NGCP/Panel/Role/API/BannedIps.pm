package NGCP::Panel::Role::API::BannedIps;

use Sipwise::Base;


use parent qw/NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Generic qw(:all);
use boolean qw(true);
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Peering::Group;
use NGCP::Panel::Utils::Peering;

sub item_name {
    return 'bannedips';
}

sub resource_name{
    return 'bannedips';
}

sub get_item_id{
    my($self, $c, $item, $resource, $form) = @_;
    return $item->{ip};
}

sub valid_id {
    my ($self, $c, $id) = @_;
    return 1 if $id=~/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?:\/\d{1,2})?$/;
    $self->error($c, HTTP_BAD_REQUEST, "Invalid id in request URI. Should be an ip address.");
    return;
}
sub item_by_id{
    my ($self, $c, $id) = @_;
    return $id;
}
1;
# vim: set tabstop=4 expandtab:
