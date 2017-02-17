package NGCP::Panel::Controller::API::PbxDeviceModelImages;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
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
    return 'Used to download the front and mac image of a <a href="#pbxdevicemodels">PbxDeviceModel</a>. Returns a binary attachment with the correct content type (e.g. image/jpeg) of the image.';
};

sub query_params {
    return [
        {
            param => 'type',
            description => 'Either "front" (default) or "mac" to download one or the other.',
            query => {
                # handled directly in role
                first => sub {},
                second => sub {},
            }
        }
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::PbxDeviceModelImages NGCP::Panel::Role::API::PbxDeviceModels/;

sub resource_name{
    return 'pbxdevicemodelimages';
}
sub dispatch_path{
    return '/api/pbxdevicemodelimages/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodelimages';
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

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return;
}

1;

# vim: set tabstop=4 expandtab:
