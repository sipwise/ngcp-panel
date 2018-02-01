package NGCP::Panel::Controller::API::CFTimeSetsItem;
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
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CFTimeSets/;

sub resource_name{
    return 'cftimesets';
}

sub dispatch_path{
    return '/api/cftimesets/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-cftimesets';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriberadmin subscriber/],
        Journal => [qw/admin reseller/],
    }
});





sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $tset = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, timeset => $tset);

        my $hal = $self->hal_from_item($c, $tset, "cftimesets");

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

        my $tset = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, timeset => $tset);
        my $old_resource = $self->hal_from_item($c, $tset, "cftimesets")->resource;
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $tset = $self->update_item($c, $tset, $old_resource, $resource, $form);
        last unless $tset;

        my $hal = $self->hal_from_item($c, $tset, "cftimesets");
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

        my $tset = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, timeset => $tset);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = undef; #unused: { $tset->get_inflated_columns };

        my $form = $self->get_form($c);
        $tset = $self->update_item($c, $tset, $old_resource, $resource, $form);
        last unless $tset;
        
        my $hal = $self->hal_from_item($c, $tset, "cftimesets");
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
        my $tset = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, timeset => $tset);
        
        last unless $self->add_delete_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            return $self->hal_from_item($c, $tset, "cftimesets"); });
        
        try {
            $tset->delete;
        } catch($e) {
            $c->log->error("Failed to delete cftimeset with id '$id': $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
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
