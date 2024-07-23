package NGCP::Panel::Controller::API::PbxDeviceConfigFiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/OPTIONS/];
}

sub api_description {
    return 'Defines the actual <a href="#pbxdevicefirmwares">PbxDeviceConfigs</a> Files.';
};

sub query_params {
    return [
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxDeviceFirmwares/;

sub resource_name{
    return 'pbxdeviceconfigfiles';
}

sub dispatch_path{
    return '/api/pbxdeviceconfigfiles/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdeviceconfigfiles';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    required_licenses => [qw/pbx device_provisioning/],
});

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    #$self->log_request($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
