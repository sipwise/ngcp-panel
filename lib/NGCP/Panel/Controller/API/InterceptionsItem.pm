package NGCP::Panel::Controller::API::InterceptionsItem;
use Sipwise::Base;
use namespace::sweep;
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Interception;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

with 'NGCP::Panel::Role::API::Interceptions';

class_has('resource_name', is => 'ro', default => 'interceptions');
class_has('dispatch_path', is => 'ro', default => '/api/interceptions/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-interceptions');

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
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, interception => $item);

        my $hal = $self->hal_from_item($c, $item);

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
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
        Accept_Patch => 'application/json-patch+json',
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $cguard = $c->model('DB')->txn_scope_guard;
    my $guard = $c->model('InterceptDB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c, 
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, interception => $item);
        my $form = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $item, $form);
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;
        my ($sub, $reseller) = $self->subres_from_number($c, $resource->{number});
        last unless($sub && $reseller);

        my $res = NGCP::Panel::Utils::Interception::request($c, 'PUT', $item->uuid, {
            number => $resource->{number},
            sip_username => $sub->username,
            sip_domain => $sub->domain->domain,
            delivery_host => $resource->{delivery_host},
            delivery_port => $resource->{delivery_port},
            delivery_user => $resource->{delivery_user},
            delivery_password => $resource->{delivery_password},
            cc_required => $resource->{cc_required},
            cc_delivery_host => $resource->{cc_delivery_host},
            cc_delivery_port => $resource->{cc_delivery_port},
        });
        unless($res) {
            $c->log->error("failed to update capture agents");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update capture agents");
            last;
        }
       
	$cguard->commit; 
        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            my $hal = $self->hal_from_item($c, $item, $form);
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

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $cguard = $c->model('DB')->txn_scope_guard;
    my $guard = $c->model('InterceptDB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, interception => $item);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $form = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $item, $form);

        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;
        my ($sub, $reseller) = $self->subres_from_number($c, $resource->{number});
        last unless($sub && $reseller);

        my $res = NGCP::Panel::Utils::Interception::request($c, 'PUT', $item->uuid, {
            number => $resource->{number},
            sip_username => $sub->username,
            sip_domain => $sub->domain->domain,
            delivery_host => $resource->{delivery_host},
            delivery_port => $resource->{delivery_port},
            delivery_user => $resource->{delivery_user},
            delivery_password => $resource->{delivery_password},
            cc_required => $resource->{cc_required},
            cc_delivery_host => $resource->{cc_delivery_host},
            cc_delivery_port => $resource->{cc_delivery_port},
        });
        unless($res) {
            $c->log->error("failed to update capture agents");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update capture agents");
            last;
        }

        $guard->commit; 

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            my $hal = $self->hal_from_item($c, $item, $form);
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

    my $cguard = $c->model('DB')->txn_scope_guard;
    my $guard = $c->model('InterceptDB')->txn_scope_guard;
    {
        my $item = $self->item_by_id($c, $id);
        my $uuid = $item->uuid;
        last unless $self->resource_exists($c, interception => $item);
        $item->update({
            deleted => 1,
            reseller_id => undef,
            LIID => undef,
            number => undef,
            cc_required => 0,
            delivery_host => undef,
            delivery_port => undef,
            delivery_user => undef,
            delivery_pass => undef,
            cc_delivery_host => undef,
            cc_delivery_port => undef,
            sip_username => undef,
            sip_domain => undef,
            uuid => undef,
        });
        my $res = NGCP::Panel::Utils::Interception::request($c, 'DELETE', $uuid);
        unless($res) {
            $c->log->error("failed to update capture agents");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update capture agents");
            last;
        }

        $guard->commit;
        $cguard->commit;

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
