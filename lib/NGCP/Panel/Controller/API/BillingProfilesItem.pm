package NGCP::Panel::Controller::API::BillingProfilesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use Clone qw/clone/;

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::BillingProfiles/;

sub resource_name{
    return 'billingprofiles';
}

sub dispatch_path{
    return '/api/billingprofiles/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-billingprofiles';
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
        my $profile = $self->profile_by_id($c, $id);
        last unless $self->resource_exists($c, billingprofile => $profile);

        my $form = $self->get_form($c);
        my $hal = $self->hal_from_item($c, $profile, $self->resource_from_item($c, $profile, $form));

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
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
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
        my $profile = $self->profile_by_id($c, $id);
        last unless $self->resource_exists($c, billingprofile => $profile);
        my $old_resource = $self->resource_from_item($c, $profile, $form);
        $old_resource = clone($old_resource);
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        $profile = $self->update_profile($c, $profile, $old_resource, $resource, $form);
        last unless $profile;

        $resource = $self->resource_from_item($c, $profile, $form);
        my $hal = $self->hal_from_item($c, $profile, $resource, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $profile = $self->profile_by_id($c, $id);
        last unless $self->resource_exists($c, billingprofile => $profile );
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        
        my $form = $self->get_form($c);
        my $old_resource = $self->resource_from_item($c, $profile, $form);

        $profile = $self->update_profile($c, $profile, $old_resource, $resource, $form);
        last unless $profile;

        $resource = $self->resource_from_item($c, $profile, $form);
        my $hal = $self->hal_from_item($c, $profile, $resource, $form);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

# we don't allow to DELETE a billing profile


sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

# vim: set tabstop=4 expandtab:
