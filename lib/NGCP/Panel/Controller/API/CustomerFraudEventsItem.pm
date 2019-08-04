package NGCP::Panel::Controller::API::CustomerFraudEventsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH/];
}
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CustomerFraudEvents/;

sub resource_name{
    return 'customerfraudevents';
}

sub dispatch_path{
    return '/api/customerfraudevents/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerfraudevents';
}

sub query_params {
    return [
        {
            param => 'interval',
            description => 'Interval filter. values: ["day", "month"].',
        },
    ];
}


__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, customerfraudevent => $item);

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
    my $schema = $c->model('DB');
    my $guard = $schema->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $item = $self->item_by_id($c, $id);
        my $json = $self->get_valid_patch_data(
            c => $c,
            id => 1, # TODO: allow non int ids in PATCH
            media_type => 'application/json-patch+json',
            ops => ["replace"],
        );
        last unless $json;

        my $form = $self->get_form($c);
        my $old_resource = $self->hal_from_item($c, $item)->resource;
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        $item = $self->update_item($c, $item, undef, $resource, $form);
        last unless $item;

        my $hal = $self->hal_from_item($c, $item);
        last unless $hal;

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
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

1;

# vim: set tabstop=4 expandtab:
