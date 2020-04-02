package NGCP::Panel::Controller::API::PeeringGroupsItem;


use Sipwise::Base;

use NGCP::Panel::Utils::Generic qw(:all);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PeeringGroups/;
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, peeringgroup => $item);

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
        last unless $self->resource_exists($c, peeringgroup => $item);
        my $old_resource = { $item->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;
        
        $guard->commit;

        $self->return_representation($c, 'item' => $item, 'form' => $form, 'preference' => $preference );
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
        last unless $self->resource_exists($c, peeringgroup => $item);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $item->get_inflated_columns };

        my $form = $self->get_form($c);
        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;

        $guard->commit; 

        $self->return_representation($c, 'item' => $item, 'form' => $form, 'preference' => $preference );
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, peeringgroup => $item);

        foreach my $p ($item->voip_peer_hosts->all) {
            if($p->probe) {
                NGCP::Panel::Utils::Peering::_sip_delete_probe(
                    c => $c,
                    ip => $p->ip,
                    port => $p->port,
                    transport => $p->transport,
                );
            }
            $p->voip_peer_preferences->delete_all;
            $p->delete;
        }
        $item->delete;
        $guard->commit;
        NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
