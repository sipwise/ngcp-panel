package NGCP::Panel::Controller::API::SoundGroupsItem;

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SoundGroups/;

use HTTP::Status qw(:constants);

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

1;

# vim: set tabstop=4 expandtab:
