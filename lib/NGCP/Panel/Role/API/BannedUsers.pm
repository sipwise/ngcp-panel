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
    return 1;
}

sub item_by_id{
    my ($self, $c, $id) = @_;
    my $list = NGCP::Panel::Utils::Security::list_banned_users($c, id => $id );
    return ref $list eq 'ARRAY' ? $list->[0] : undef ;
}


1;
# vim: set tabstop=4 expandtab:
