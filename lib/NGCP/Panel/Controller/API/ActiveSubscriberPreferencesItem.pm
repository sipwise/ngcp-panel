package NGCP::Panel::Controller::API::ActiveSubscriberPreferencesItem;

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub container_resource_type{
    return 'active';
}

sub resource_name{
    return 'activesubscriberpreferences';
}

1;

# vim: set tabstop=4 expandtab:
