package NGCP::Panel::Controller::API::TrustedSourcesItem;
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

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::TrustedSources/;

sub resource_name{
    return 'trustedsources';
}

sub dispatch_path{
    return '/api/trustedsources/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-trustedsources';
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
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, trustedsource => $item);

        my $hal = $self->hal_from_item($c, $item);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-\w+)"|rel="item $1"|r =~
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
        last unless $self->resource_exists($c, trustedsource => $item);
        my $form = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $item, $form);
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        $item = $self->update_item($c, $item, $old_resource, $resource, $form);
        last unless $item;
        
        my $hal = $self->hal_from_item($c, $item, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit;

        try {
            my (undef, $xmlrpc_res) = NGCP::Panel::Utils::Kamailio::trusted_reload($c);
            if (!defined $xmlrpc_res || $xmlrpc_res < 1) {
                die "XMLRPC failed";
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to reload kamailio. Trusted source was modified.", $e);
            last;
        }

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $item, $form);
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

        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, trustedsource => $item);
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

        my $hal = $self->hal_from_item($c, $item, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit;

        try {
            my (undef, $xmlrpc_res) = NGCP::Panel::Utils::Kamailio::trusted_reload($c);
            if (!defined $xmlrpc_res || $xmlrpc_res < 1) {
                die "XMLRPC failed";
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to reload kamailio. Trusted source was modified.", $e);
            # TODO: do we still want to return the modified item here?
            last;
        }

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_item($c, $item, $form);
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

sub DELETE :Allow {
    my ($self, $c, $id) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, trustedsource => $item);
        
        last unless $self->add_delete_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_form = $self->get_form($c);
            return $self->hal_from_item($c, $item, $_form); });
        
        $item->delete;

        $guard->commit;

        try {
            my (undef, $xmlrpc_res) = NGCP::Panel::Utils::Kamailio::trusted_reload($c);
            if (!defined $xmlrpc_res || $xmlrpc_res < 1) {
                die "XMLRPC failed";
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to reload kamailio. Trusted source was deleted.", $e);
            last;
        }

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
