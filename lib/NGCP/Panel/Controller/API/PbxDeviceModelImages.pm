package NGCP::Panel::Controller::API::PbxDeviceModelImages;
use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Used to download the front and mac image of a <a href="#pbxdevicemodels">PbxDeviceModel</a>. Returns a binary attachment with the correct content type (e.g. image/jpeg) of the image.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'type',
            description => 'Either "front" (default) or "mac" to download one or the other.',
            query => {
                # handled directly in role
                first => sub {},
                second => sub {},
            }
        }
    ]},
);

with 'NGCP::Panel::Role::API::PbxDeviceModelImages';
with 'NGCP::Panel::Role::API::PbxDeviceModels';

class_has('resource_name', is => 'ro', default => 'pbxdevicemodelimages');
class_has('dispatch_path', is => 'ro', default => '/api/pbxdevicemodelimages/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodelimages');

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
    action_roles => [qw(HTTPMethods)],
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
        Allow => $allowed_methods->join(', '),
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

# vim: set tabstop=4 expandtab:
