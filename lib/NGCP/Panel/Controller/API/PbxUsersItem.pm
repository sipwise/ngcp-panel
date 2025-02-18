package NGCP::Panel::Controller::API::PbxUsersItem;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PbxUsers/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Status qw(:constants);

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller ccareadmin ccare subscriberadmin subscriber/],
    },
});

1;

# vim: set tabstop=4 expandtab:
