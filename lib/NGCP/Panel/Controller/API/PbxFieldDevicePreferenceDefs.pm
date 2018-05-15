package NGCP::Panel::Controller::API::PbxFieldDevicePreferenceDefs;

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntityPreferenceDefs NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Preferences;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

__PACKAGE__->set_config({
    preferences_group => 'fielddev_pref',
    allowed_roles    => [qw/admin reseller/],
});

1;

# vim: set tabstop=4 expandtab:
