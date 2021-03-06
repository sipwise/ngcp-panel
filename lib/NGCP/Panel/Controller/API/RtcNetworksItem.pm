package NGCP::Panel::Controller::API::RtcNetworksItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::RtcNetworks/;

sub resource_name{
    return 'rtcnetworks';
}

sub dispatch_path{
    return '/api/rtcnetworks/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-rtcnetworks';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller/],
        Journal => [qw/admin reseller/],
    }
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, reseller => $item);

        my $hal = $self->hal_from_item($c, $item);

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

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $schema = $c->model('DB');
    my $guard = $schema->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $reseller = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, reseller => $reseller);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);
        my $old_resource = $self->hal_from_item($c, $reseller, 1)->resource;
        $reseller = $self->update_item($c, $reseller, $old_resource, $resource, $form);
        last unless $reseller;

        my $hal = $self->hal_from_item($c, $reseller);
        last unless $self->add_update_journal_item_hal($c,{ hal => $hal, id => $reseller->id });

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $reseller);
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

        my $reseller = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, reseller => $reseller);
        my $json = $self->get_valid_patch_data(
            c => $c,
            id => $id,
            media_type => 'application/json-patch+json',
            ops => ["add", "replace", "copy", "remove"],
        );
        last unless $json;

        my $form = $self->get_form($c);
        my $old_resource = $self->hal_from_item($c, $reseller, 1)->resource;
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        $reseller = $self->update_item($c, $reseller, $old_resource, $resource, $form);
        last unless $reseller;

        my $hal = $self->hal_from_item($c, $reseller);
        last unless $self->add_update_journal_item_hal($c,{ hal => $hal, id => $reseller->id });

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $reseller);
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

sub item_base_journal :Journal {
    my $self = shift @_;
    return $self->handle_item_base_journal(@_);
}

sub journals_get :Journal {
    my $self = shift @_;
    return $self->handle_journals_get(@_);
}

sub journalsitem_get :Journal {
    my $self = shift @_;
    return $self->handle_journalsitem_get(@_);
}

sub journals_options :Journal {
    my $self = shift @_;
    return $self->handle_journals_options(@_);
}

sub journalsitem_options :Journal {
    my $self = shift @_;
    return $self->handle_journalsitem_options(@_);
}

sub journals_head :Journal {
    my $self = shift @_;
    return $self->handle_journals_head(@_);
}

sub journalsitem_head :Journal {
    my $self = shift @_;
    return $self->handle_journalsitem_head(@_);
}

1;

# vim: set tabstop=4 expandtab:
