package NGCP::Panel::Controller::API::BillingFeesItem;
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

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::BillingFees/;

sub resource_name{
    return 'billingfees';
}

sub dispatch_path{
    return '/api/billingfees/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-billingfees';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    required_licenses => [qw/billing/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $fee = $self->fee_by_id($c, $id);
        last unless $self->resource_exists($c, billingfee => $fee);

        my $hal = $self->hal_from_fee($c, $fee);

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

        my $fee = $self->fee_by_id($c, $id);
        last unless $self->resource_exists($c, billingfee => $fee);
        my $old_resource = { $fee->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $fee = $self->update_fee($c, $fee, $old_resource, $resource, $form);
        last unless $fee;

        $guard->commit;
        my $hal = $self->hal_from_fee($c, $fee, $form);
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

        my $fee = $self->fee_by_id($c, $id);
        last unless $self->resource_exists($c, billingfee => $fee);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $fee->get_inflated_columns };

        my $form = $self->get_form($c);
        $fee = $self->update_fee($c, $fee, $old_resource, $resource, $form);
        last unless $fee;

        $guard->commit;
        my $hal = $self->hal_from_fee($c, $fee, $form);
        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $fee = $self->fee_by_id($c, $id);
        last unless $self->resource_exists($c, billingfee => $fee);

        try {
            $fee->delete;
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                         "Failed to delete billing fee with id '$id'", $e);
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
