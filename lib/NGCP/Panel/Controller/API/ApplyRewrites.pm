package NGCP::Panel::Controller::API::ApplyRewrites;
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

with 'NGCP::Panel::Role::API::ApplyRewrites';

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Applies rewrite rules to a given number according to the given direction. It can for example be used to normalize user input to E164 using callee_in direction, or to denormalize E164 to user output using caller_out.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
    ]},
);

class_has('resource_name', is => 'ro', default => 'applyrewrites');
class_has('dispatch_path', is => 'ro', default => '/api/applyrewrites/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-applyrewrites');

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
    my $allowed_methods = $self->allowed_methods_filtered($c);
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

        my $subscriber_rs = $c->model('DB')->resultset('voip_subscribers')->search({
            'me.id' => $resource->{subscriber_id},
            'me.status' => { '!=' => 'terminated' },
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

        my $normalized;
        try {

            $normalized = NGCP::Panel::Utils::Subscriber::apply_rewrite(
                c => $c, subscriber => $subscriber, 
                number => $resource->{number}, direction => $resource->{direction},
            );
        } catch($e) {
            $c->log->error("failed to rewrite number: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to rewrite number.");
            last;
        }

        $guard->commit;

        my $res = '{ "result": "'.$normalized.'" }'."\n";

        $c->response->status(HTTP_OK);
        $c->response->body($res);
    }
    return;
}


sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
