package NGCP::Panel::Controller::API::BillingProfilesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Billing qw /check_profile_update_item/;
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT DELETE/];
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
        Default => [qw/admin reseller ccareadmin ccare/],
        Journal => [qw/admin reseller ccareadmin ccare/],
    }
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $profile = $self->profile_by_id($c, $id);
        last unless $self->resource_exists($c, billingprofile => $profile);

        my $hal = $self->hal_from_profile($c, $profile);

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

        if ($c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            last;
        }

        my $profile = $self->profile_by_id($c, $id);
        last unless $self->resource_exists($c, billingprofile => $profile);
        my $old_resource = { $profile->get_inflated_columns };
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $profile = $self->update_profile($c, $profile, $old_resource, $resource, $form);
        last unless $profile;

        my $hal = $self->hal_from_profile($c, $profile, $form);
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

        if ($c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            last;
        }

        my $profile = $self->profile_by_id($c, $id);
        last unless $self->resource_exists($c, billingprofile => $profile );
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $profile->get_inflated_columns };

        my $form = $self->get_form($c);
        $profile = $self->update_profile($c, $profile, $old_resource, $resource, $form);
        last unless $profile;

        my $hal = $self->hal_from_profile($c, $profile, $form);
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
       if ($c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
           $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
           last;
       }

       my $billing_profile = $self->item_by_id($c, $id);
       last unless $self->resource_exists($c, billingprofile => $billing_profile);
       last unless NGCP::Panel::Utils::Reseller::check_reseller_delete_item($c, $billing_profile->reseller_id, sub {
           my ($err) = @_;
           $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
       });
       return unless NGCP::Panel::Utils::Billing::check_profile_update_item($c,undef,$billing_profile,sub {
            my ($err) = @_;
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, $err);
        });
       try {
           $billing_profile->update({
                status => 'terminated',
                terminate_timestamp => NGCP::Panel::Utils::DateTime::current_local
            });
       } catch($e) {
           $c->log->error("Failed to terminate billingprofile with id '$id': $e");
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
