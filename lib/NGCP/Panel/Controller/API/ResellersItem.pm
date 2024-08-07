package NGCP::Panel::Controller::API::ResellersItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use Clone qw/clone/;
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Resellers/;

sub resource_name{
    return 'resellers';
}

sub dispatch_path{
    return '/api/resellers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-resellers';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin/],
        Journal => [qw/admin/],
    },
    required_licenses => {
        PATCH => [qw/reseller/],
        PUT => [qw/reseller/],
    }
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $reseller = $self->reseller_by_id($c, $id);
        last unless $self->resource_exists($c, reseller => $reseller);

        my $hal = $self->hal_from_reseller($c, $reseller);

        # TODO: huh?
        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-resellers)"|rel="item $1"|r =~
                s/rel=self/rel="item self"/r;
            } $hal->http_headers(skip_links => 1)),
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

        my $form = $self->get_form($c);

        my $reseller = $self->reseller_by_id($c, $id);
        last unless $self->resource_exists($c, reseller => $reseller);
        my $old_resource = $self->hal_from_reseller($c, $reseller, $form)->resource;
        #without it error: The entity could not be processed: Modification of a read-only value attempted at /usr/share/perl5/JSON/Pointer.pm line 200, <$fh> line 1.\n
        #But really I don't understand why $old_resource is read-only. resource is rw in Data::HAL
        $old_resource = clone($old_resource);
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        $reseller = $self->update_reseller($c, $reseller, $old_resource, $resource, $form);
        last unless $reseller;

        my $hal = $self->hal_from_reseller($c, $reseller, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_reseller($c, $reseller, $form);
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

        my $reseller = $self->reseller_by_id($c, $id);
        last unless $self->resource_exists($c, reseller => $reseller );
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $form = $self->get_form($c);
        my $old_resource = $self->hal_from_reseller($c, $reseller, $form)->resource;

        $reseller = $self->update_reseller($c, $reseller, $old_resource, $resource, $form);
        last unless $reseller;

        my $hal = $self->hal_from_reseller($c, $reseller, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_reseller($c, $reseller, $form);
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

# we don't allow to DELETE a reseller?

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
