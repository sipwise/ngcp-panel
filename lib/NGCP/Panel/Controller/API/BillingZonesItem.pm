package NGCP::Panel::Controller::API::BillingZonesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::BillingZones/;

sub resource_name{
    return 'billingzones';
}

sub dispatch_path{
    return '/api/billingzones/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-billingzones';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller/],
        Journal => [qw/admin reseller/],
    },
    required_licenses => [qw/billing/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $zone = $self->zone_by_id($c, $id);
        last unless $self->resource_exists($c, billingzone => $zone);

        my $hal = $self->hal_from_zone($c, $zone);

        # TODO: we don't need reseller stuff here!
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

        my $zone = $self->zone_by_id($c, $id);
        last unless $self->resource_exists($c, billingzone => $zone);
        my $old_resource = { $zone->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $zone = $self->update_zone($c, $zone, $old_resource, $resource, $form);
        last unless $zone;

        my $hal = $self->hal_from_zone($c, $zone, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit;

        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $zone = $self->zone_by_id($c, $id);
        last unless $self->resource_exists($c, billingzone => $zone);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $zone->get_inflated_columns };

        my $form = $self->get_form($c);
        $zone = $self->update_zone($c, $zone, $old_resource, $resource, $form);
        last unless $zone;

        my $hal = $self->hal_from_zone($c, $zone, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit;

        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $zone = $self->zone_by_id($c, $id);
        last unless $self->resource_exists($c, billingzone => $zone);
        
        last unless $self->add_delete_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_form = $self->get_form($c);
            return $self->hal_from_zone($c, $zone, $_form); });
        
        try {
            $zone->billing_fees->delete_all;
            $zone->delete;
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                         "Failed to delete billing zone with id '$id'", $e);
            last;
        }
        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
