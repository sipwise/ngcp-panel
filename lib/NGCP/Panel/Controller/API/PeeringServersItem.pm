package NGCP::Panel::Controller::API::PeeringServersItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

use NGCP::Panel::Utils::Peering;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PeeringServers/;

sub resource_name{
    return 'peeringservers';
}

sub dispatch_path{
    return '/api/peeringservers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-peeringservers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, peeringserver => $item);

        my $hal = $self->hal_from_item($c, $item);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r =~
                s/rel=self/rel="item self"/r;
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub PATCH :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
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
        last unless $self->resource_exists($c, peeringserver => $item);
        my $old_resource = { $item->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $peer_disabled  = $old_resource->{enabled} && !$resource->{enabled};
        my $peer_enabled   = !$old_resource->{enabled} && $resource->{enabled};
        my $probe_disabled = $old_resource->{probe} && !$resource->{probe};
        my $probe_enabled  = !$old_resource->{probe} && $resource->{probe};
        my $probe_updated  = $peer_disabled || $peer_enabled || $probe_disabled || $probe_enabled;

        try {
            if ($peer_disabled) {
                NGCP::Panel::Utils::Peering::sip_delete_peer_registration(
                    c => $c,
                    prov_peer => $item
                );
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update peering server.",
                         "failed to delete peer registration", $e);
            last;
        }

        try {
            if ($peer_disabled || $probe_disabled) {
                NGCP::Panel::Utils::Peering::sip_delete_probe(
                    c => $c,
                    ip => $item->ip,
                    port => $item->port,
                    transport => $item->transport,
                );
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update peering server.",
                         "failed to delete probe", $e);
            last;
        }

        my $form = $self->get_form($c);
        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;

        try {
            if ($peer_enabled) {
                NGCP::Panel::Utils::Peering::sip_create_peer_registration(
                    c => $c,
                    prov_peer => $item
                );
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update peering server.",
                         "failed to create peer registration", $e);
            last;
        }

        $guard->commit;

        if ($probe_updated) {
            NGCP::Panel::Utils::Peering::sip_dispatcher_reload(c => $c);
        }

        NGCP::Panel::Utils::Peering::sip_lcr_reload(c => $c);

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
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, peeringserver => $item);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $item->get_inflated_columns };

        my $peer_disabled  = $old_resource->{enabled} && !$resource->{enabled};
        my $peer_enabled   = !$old_resource->{enabled} && $resource->{enabled};
        my $probe_disabled = $old_resource->{probe} && !$resource->{probe};
        my $probe_enabled  = !$old_resource->{probe} && $resource->{probe};
        my $probe_updated  = $peer_disabled || $peer_enabled || $probe_disabled || $probe_enabled;

        try {
            if ($peer_disabled) {
                NGCP::Panel::Utils::Peering::sip_delete_peer_registration(
                    c => $c,
                    prov_peer => $item
                );
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update peering server.",
                         "failed to delete peer registration", $e);
            last;
        }

        try {
            if (($peer_disabled || $probe_disabled) {
                NGCP::Panel::Utils::Peering::sip_delete_probe(
                    c => $c,
                    ip => $item->ip,
                    port => $item->port,
                    transport => $item->transport,
                );
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update peering server.",
                         "failed to delete probe", $e);
            last;
        }

        my $form = $self->get_form($c);
        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;

        try {
            if ($peer_enabled) {
                NGCP::Panel::Utils::Peering::sip_create_peer_registration(
                    c => $c,
                    prov_peer => $item
                );
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to update peering server.",
                         "failed to create peer registration", $e);
            last;
        }

        $guard->commit;

        if ($probe_updated) {
            NGCP::Panel::Utils::Peering::sip_dispatcher_reload(c => $c);
        }

        NGCP::Panel::Utils::Peering::sip_lcr_reload(c => $c);

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

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, peeringserver => $item);

        my $probe_updated = 0;

        try {
            if ($item->enabled) {
                NGCP::Panel::Utils::Peering::sip_delete_peer_registration(
                    c => $c, prov_peer => $item
                );
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to delete peering server.",
                "failed to delete peer registration", $e);
            last;
        }

        try {
            if($item->probe) {
                NGCP::Panel::Utils::Peering::sip_delete_probe(
                    c => $c,
                    ip => $item->ip,
                    port => $item->port,
                    transport => $item->transport,
                );
                $probe_updated = 1;
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to delete peering server.",
                "failed to reload kamailio cache", $e);
            last;
        }

        $item->delete;
        $guard->commit;

        if ($probe_updated) {
            NGCP::Panel::Utils::Peering::sip_dispatcher_reload(c => $c);
        }

        NGCP::Panel::Utils::Peering::sip_lcr_reload(c => $c);

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
