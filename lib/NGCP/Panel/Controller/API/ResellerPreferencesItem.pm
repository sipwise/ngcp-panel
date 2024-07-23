package NGCP::Panel::Controller::API::ResellerPreferencesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    PATCH => { ops => [qw/add replace remove copy/] },
    allowed_roles => [qw/admin reseller/],
    required_licenses => [qw/reseller/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

sub item_name{
    return 'resellerpreference';
}

sub resource_name{
    return 'resellerpreferences';
}

sub container_resource_type{
    return 'resellers';
}

1;

# vim: set tabstop=4 expandtab:
