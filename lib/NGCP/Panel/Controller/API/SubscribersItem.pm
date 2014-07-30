package NGCP::Panel::Controller::API::SubscribersItem;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API::Subscribers';

class_has('resource_name', is => 'ro', default => 'subscribers');
class_has('dispatch_path', is => 'ro', default => '/api/subscribers/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-subscribers');

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 1,
            Does => [qw(ACL RequireSSL)],
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
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $subscriber = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, subscriber => $subscriber);

        my $form = $self->get_form($c);
        my $resource = $self->resource_from_item($c, $subscriber, $form);
        my $hal = $self->hal_from_item($c, $subscriber, $resource, $form);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|;
                s/rel=self/rel="item self"/;
                $_
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub HEAD :Allow {
    my ($self, $c, $id) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c, $id) = @_;
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $schema = $c->model('DB');
    my $guard = $schema->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $subscriber = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, subscriber => $subscriber);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $r = $self->prepare_resource($c, $schema, $resource, $subscriber);
        last unless $r;
        $resource = $r->{resource};

        my $form = $self->get_form($c);
        $subscriber = $self->update_item($c, $schema, $subscriber, $r, $resource, $form);
        last unless $subscriber;

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            $resource = $self->resource_from_item($c, $subscriber, $form);
            my $hal = $self->hal_from_item($c, $subscriber, $resource, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}

sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $schema = $c->model('DB');
    my $guard = $schema->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $subscriber = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, subscriber => $subscriber);
        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
            ops => ["add", "replace", "copy", "remove"],
        );
        last unless $json;

        my $form = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $subscriber, $form);
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $update = 1;
        my $r = $self->prepare_resource($c, $schema, $resource, $subscriber);
        last unless $r;
        $resource = $r->{resource};

        $subscriber = $self->update_item($c, $schema, $subscriber, $r, $resource, $form);
        last unless $subscriber;

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            $resource = $self->resource_from_item($c, $subscriber, $form);
            my $hal = $self->hal_from_item($c, $subscriber, $resource, $form);
            my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                $hal->http_headers,
            ), $hal->as_json);
            $c->response->headers($response->headers);
            $c->response->header(Preference_Applied => 'return=representation');
            $c->response->body($response->content);
        }
    }
    return;
}


sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $subscriber = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, subscriber => $subscriber);

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            my $contact = $subscriber->contract->contact;
            unless($contact && $contact->reseller_id == $c->user->reseller_id) {
                $self->error($c, HTTP_FORBIDDEN, "subscriber does not belong to reseller");
                last;
            }
        }

        NGCP::Panel::Utils::Subscriber::terminate(c => $c, subscriber => $subscriber);

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

# vim: set tabstop=4 expandtab:
