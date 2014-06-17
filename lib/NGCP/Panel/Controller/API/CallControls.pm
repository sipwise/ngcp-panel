package NGCP::Panel::Controller::API::CallControls;
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

use NGCP::Panel::Utils::Sems;

BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Allows to place calls via the API.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
    ]},
);

with 'NGCP::Panel::Role::API::CallControls';

class_has('resource_name', is => 'ro', default => 'callcontrols');
class_has('dispatch_path', is => 'ro', default => '/api/callcontrols/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-callcontrols');

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

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub POST :Allow {
    my ($self, $c) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
            exceptions => [qw/subscriber_id/],
        );

        # TODO: fetch subscriber by id

        my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            id => $resource->{subscriber_id},
            status => { '!=' => 'terminated' },
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $subscriber_rs = $subscriber_rs->search({
                'contact.reseller_id' => $c->user->reseller_id,
            },{
                join => { contract => 'contact' },
            });
        }
        my $subscriber = $subscriber_rs->first;
        unless($subscriber) {
            $c->log->error("invalid subscriber id $$resource{subscriber_id} for outbound call");
            $self->error($c, HTTP_NOT_FOUND, "Calling subscriber not found.");
            last;
        }

        my ($callee_user, $callee_domain) = split /\@/, $resource->{destination};
        $callee_domain //= $subscriber->domain->domain;

        try {
            NGCP::Panel::Utils::Sems::dial_out($c, $subscriber->provisioning_voip_subscriber,
                $callee_user, $callee_domain);
        } catch($e) {
            $c->log->error("failed to dial out: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create call.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_OK);
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
