package NGCP::Panel::Controller::API::InterceptionsItem;

use Sipwise::Base;
no Moose;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Interception;
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Interceptions/;

sub resource_name{
    return 'interceptions';
}

sub dispatch_path{
    return '/api/interceptions/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-interceptions';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller lintercept/],
});

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    #$self->log_request($c);

    unless($c->user->lawful_intercept) {
        $self->error($c, HTTP_FORBIDDEN, "Accessing user has no LI privileges.");
        return;
    }
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
    
        $guard->commit;
        $cguard->commit; 
        $self->return_representation($c, 'item' => $item, 'form' => $form, 'preference' => $preference );
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

        $guard->commit; 
        $cguard->commit; 
        $self->return_representation($c, 'item' => $item, 'form' => $form, 'preference' => $preference );
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

sub filter_log_response {
    my ($self, $c, $response_body, $params_data) = @_;

    $response_body //= "";
    $response_body =~ s!([+0-9]{2,})([0-9]{2})!***$2!g; # hide strings which look like a number

    return ($response_body, $params_data);
}

1;

# vim: set tabstop=4 expandtab:
