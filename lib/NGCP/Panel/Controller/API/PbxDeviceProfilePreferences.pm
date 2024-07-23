package NGCP::Panel::Controller::API::PbxDeviceProfilePreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    required_licenses => [qw/pbx device_provisioning/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub item_name{
    return 'pbxdeviceprofilepreference';
}

sub resource_name{
    return 'pbxdeviceprofilepreferences';
}

sub container_resource_type{
    return 'pbxdeviceprofiles';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#pbxdeviceprofiles">PBX Device Profiles</a>. The full list of properties can be obtained via <a href="/api/pbxdeviceprofilepreferencedefs/">PbxDeviceProfilePreferenceDefs</a>.';
};

1;

# vim: set tabstop=4 expandtab:
