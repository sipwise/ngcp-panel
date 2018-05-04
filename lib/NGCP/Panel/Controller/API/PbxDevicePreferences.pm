package NGCP::Panel::Controller::API::PbxDevicePreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub item_name{
    return 'pbxdevicepreference';
}

sub resource_name{
    return 'pbxdevicepreferences';
}

sub container_resource_type{
    return 'pbxdevicemodels';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#pbxdevicemodels">PBX Device Models</a>. The full list of properties can be obtained via <a href="/api/pbxdevicepreferencedefs/">PbxDevicePreferenceDefs</a>.';
};

1;

# vim: set tabstop=4 expandtab:
