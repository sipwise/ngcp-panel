package NGCP::Panel::Controller::API::SubscriberRegistrationsItem;
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

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SubscriberRegistrations/;

sub resource_name{
    return 'subscriberregistrations';
}

sub dispatch_path{
    return '/api/subscriberregistrations/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-subscriberregistrations';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare subscriber subscriberadmin/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, subscriberregistration => $item);

        my $hal = $self->hal_from_item($c, $item);
        unless($hal) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid location entry");
            last;
        }

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

    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $form = $self->get_form($c);
        last unless $form;

        my ($item, $old_resource, $resource);
        my ($guard, $txn_ok) = ($c->model('DB')->txn_scope_guard, 0);
        {
            $item = $self->item_by_id($c, $id);
            last unless $self->resource_exists($c, subscriberregistration => $item);

            $old_resource = $self->resource_from_item($c, $item, $form);

            $resource = $self->apply_patch($c, $old_resource, $json);
            last unless $resource;

            $item = $self->update_item($c, $item, $old_resource, $resource, $form);
            last unless $item;

            $guard->commit;
            $txn_ok = 1;
        }
        last unless $txn_ok;

        $item = $self->fetch_item($c, $resource, $form, $item);

        if ($item) {
            if ('minimal' eq $preference) {
                $c->response->status(HTTP_NO_CONTENT);
                $c->response->header(Preference_Applied => 'return=minimal');
                $c->response->header(Location => sprintf('%s%s', $self->dispatch_path, $item->id));
                $c->response->body(q());
            } else {
                my $hal = $self->hal_from_item($c, $item, $form);
                my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                    $hal->http_headers,
                ), $hal->as_json);
                $c->response->headers($response->headers);
                $c->response->header(Preference_Applied => 'return=representation');
                $c->response->header(Location => sprintf('%s%s', $self->dispatch_path, $item->id));
                $c->response->body($response->content);
            }
        } else {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->body(q());            
        }
    }

    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;

    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $form = $self->get_form($c);
        last unless $form;

        my ($item, $old_resource, $resource);
        my ($guard, $txn_ok) = ($c->model('DB')->txn_scope_guard, 0);
        {
            $item = $self->item_by_id($c, $id);
            last unless $self->resource_exists($c, subscriberregistration => $item);

            $old_resource = $self->resource_from_item($c, $item, $form);

            $resource = $self->get_valid_put_data(
                c => $c,
                id => $id,
                media_type => 'application/json',
            );
            last unless $resource;

            $item = $self->update_item($c, $item, $old_resource, $resource, $form);
            last unless $item;

            $guard->commit;
            $txn_ok = 1;
        }
        last unless $txn_ok;

        $item = $self->fetch_item($c, $resource, $form, $item);

        if ($item) {
            if ('minimal' eq $preference) {
                $c->response->status(HTTP_NO_CONTENT);
                $c->response->header(Preference_Applied => 'return=minimal');
                $c->response->header(Location => sprintf('%s%s', $self->dispatch_path, $item->id));
                $c->response->body(q());
            } else {
                my $hal = $self->hal_from_item($c, $item, $form);
                my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
                    $hal->http_headers,
                ), $hal->as_json);
                $c->response->headers($response->headers);
                $c->response->header(Preference_Applied => 'return=representation');
                $c->response->header(Location => sprintf('%s%s', $self->dispatch_path, $item->id));
                $c->response->body($response->content);
            }
        } else {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->body(q());            
        }
    }

    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;

    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, subscriberregistration => $item);
        $self->delete_item($c, $item);

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

sub delete_item {
    my ($self, $c, $item) = @_;

    my $sub = $self->subscriber_from_item($c, $item);
    return unless($sub);
    NGCP::Panel::Utils::Kamailio::delete_location_contact($c,
        $sub, $item->contact);
    NGCP::Panel::Utils::Kamailio::flush($c) unless $self->suppress_flush($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
