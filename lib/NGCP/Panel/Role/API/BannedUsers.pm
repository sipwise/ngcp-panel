package NGCP::Panel::Role::API::BannedUsers;

use Sipwise::Base;


use parent qw/NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Generic qw(:all);
use boolean qw(true);
use HTTP::Status qw(:constants);

sub item_name {
    return 'bannedusers';
}

sub resource_name{
    return 'bannedusers';
}

sub get_item_id{
    my($self, $c, $item, $resource, $form) = @_;
    return $item->{username};
}

sub valid_id {
    my ($self, $c, $id) = @_;
    return 1 if $id=~/^[^@]+@[^@]+$/;
    $self->error($c, HTTP_BAD_REQUEST, "Invalid id in request URI. Should be an ip address.");
    return;
}

sub item_by_id{
    my ($self, $c, $id) = @_;
    return $id;
}


1;
# vim: set tabstop=4 expandtab:
