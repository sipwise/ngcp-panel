package NGCP::Panel::Controller::API::CustomerLocationsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Reseller qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CustomerLocations/;

sub resource_name{
    return 'customerlocations';
}

sub dispatch_path{
    return '/api/customerlocations/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerlocations';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller ccareadmin ccare/],
        Journal => [qw/admin reseller ccareadmin ccare/],
    }
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $cl = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, customerlocation => $cl);

        my $hal = $self->hal_from_item($c, $cl, $self->resource_name);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r
                =~ s/rel=self/rel="item self"/r;
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
            ops => [qw/add replace remove copy/],
        );
        last unless $json;

        my $cl = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, customerlocation => $cl);
        my $old_resource = $self->hal_from_item($c, $cl, $self->resource_name)->resource;
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $cl = $self->update_item($c, $cl, $old_resource, $resource, $form);
        last unless $cl;

        my $hal = $self->hal_from_item($c, $cl, $self->resource_name);
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

        my $cl = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, customerlocation => $cl);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $cl->get_inflated_columns };

        my $form = $self->get_form($c);
        $cl = $self->update_item($c, $cl, $old_resource, $resource, $form);
        last unless $cl;
        
        my $hal = $self->hal_from_item($c, $cl, $self->resource_name);
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
        my $cl = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, customerlocation => $cl);
        try {
            $cl->delete;
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                         "Failed to delete customre location with id '$id'", $e);
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
