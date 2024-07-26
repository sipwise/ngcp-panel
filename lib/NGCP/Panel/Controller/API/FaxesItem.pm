package NGCP::Panel::Controller::API::FaxesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Faxes/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    required_licenses => [qw/fax/],
    dont_validate_hal => 1,
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD DELETE/];
}

1;

# vim: set tabstop=4 expandtab:
