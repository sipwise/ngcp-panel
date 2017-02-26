package NGCP::Panel::Controller::API::PbxDeviceConfigFiles;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    #$self->log_request($c);
    return 1;
}



sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return;
}

1;

# vim: set tabstop=4 expandtab:
