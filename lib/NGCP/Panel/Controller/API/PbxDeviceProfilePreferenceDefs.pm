package NGCP::Panel::Controller::API::PbxDeviceProfilePreferenceDefs;

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::EntityPreferenceDefs NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Preferences;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

__PACKAGE__->set_config({
    preferences_group => 'devprof_pref',
    allowed_roles    => [qw/admin reseller/],
    required_licenses => [qw/pbx device_provisioning/],
});

1;

# vim: set tabstop=4 expandtab:
