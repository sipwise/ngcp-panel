package NGCP::Panel::Controller::API::PbxDevicePreferencesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Preferences/;

sub resource_name{
    return 'pbxdevicepreferences';
}

sub dispatch_path{
    return '/api/pbxdevicepreferences/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicepreferences';
}

sub container_resource_type {
    return 'pbxdevicemodels';
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
        my $container_type = "pbxdevicemodels";
        my $preferences_type = "pbxdevicepreference";
        my $container_item = $self->item_by_id($c, $id, $container_type);
        last unless $self->resource_exists($c, $preferences_type => $container_item);

        my $hal = $self->hal_from_item($c, $container_item, $container_type);

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

        my $container_type = "pbxdevicemodels";
        my $preferences_type = "pbxdevicepreference";
        my $container_item = $self->item_by_id($c, $id, $container_type);
        last unless $self->resource_exists($c, $preferences_type => $container_item);
        my $old_resource = $self->get_resource($c, $container_item, $container_type);
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        # last param is "no replace" to NOT delete existing prefs
        # for proper PATCH behavior
        $container_item = $self->update_item($c, $container_item, $old_resource, $resource, 0, $container_type);
        last unless $container_item;

        my $hal = $self->hal_from_item($c, $container_item, $container_type);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit; 

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $container_item, $container_type);
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

        my $container_type = "pbxdevicemodels";
        my $preferences_type = "pbxdevicepreference";
        my $container_item = $self->item_by_id($c, $id, $container_type);
        # TODO: systemcontact?
        last unless $self->resource_exists($c, $preferences_type => $container_item);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = $self->get_resource($c, $container_item, $container_type);

        # last param is "replace" to delete all existing prefs
        # for proper PUT behavior
        $container_item = $self->update_item($c, $container_item, $old_resource, $resource, 1, $container_type);
        last unless $container_item;

        my $hal = $self->hal_from_item($c, $container_item, $container_type);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit; 

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $container_item, $container_type);
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

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
} 



1;

# vim: set tabstop=4 expandtab:
