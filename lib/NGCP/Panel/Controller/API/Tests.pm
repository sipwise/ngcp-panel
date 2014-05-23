package NGCP::Panel::Controller::API::Tests;
use Sipwise::Base;
use namespace::sweep;
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

with 'NGCP::Panel::Role::API';

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Defines test (wake-up call) settings for subscribers.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
    ]},
);

class_has('resource_name', is => 'ro', default => 'tests');
class_has('dispatch_path', is => 'ro', default => '/api/tests/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-tests');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

sub GET :Allow {
    my ($self, $c) = @_;
    {
        my $res = "";
        my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find(45);
        use NGCP::Panel::Utils::Subscriber;
        for my $n (qw/12345 012345 004312345/) {
            my $nn = NGCP::Panel::Utils::Subscriber::normalize_callee(
                c => $c, subscriber => $subscriber, number => $n,
            );
            $res .= "$nn;";

        }
        $c->response->body($res);
        return;
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
