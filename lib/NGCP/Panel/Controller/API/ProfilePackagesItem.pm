package NGCP::Panel::Controller::API::ProfilePackagesItem;
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

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::ProfilePackages/;

sub resource_name{
    return 'profilepackages';
}

sub dispatch_path{
    return '/api/profilepackages/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-profilepackages';
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
        my $package = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, profilepackage => $package);

        my $hal = $self->hal_from_item($c, $package, "profilepackages");

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
    {
        if ($c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            last;
        }

        my $preference = $self->require_preference($c);
        last unless $preference;

        my $json = $self->get_valid_patch_data(
            c => $c, 
            id => $id,
            media_type => 'application/json-patch+json',
        );
        last unless $json;

        my $package = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, profilepackage => $package);
        my $old_resource = $self->hal_from_item($c, $package, "profilepackages")->resource;
        my $resource = $self->apply_patch($c, $old_resource, $json);
        last unless $resource;

        my $form = $self->get_form($c);
        $package = $self->update_item($c, $package, $old_resource, $resource, $form);
        last unless $package;
        
        my $hal = $self->hal_from_item($c, $package, "profilepackages", $form);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_profile($c, $package, $form);
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
        if ($c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            last;
        }

        my $preference = $self->require_preference($c);
        last unless $preference;

        my $package = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, profilepackage => $package );
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $package->get_inflated_columns };

        my $form = $self->get_form($c);
        $package = $self->update_item($c, $package, $old_resource, $resource, $form);
        last unless $package;

        my $hal = $self->hal_from_item($c, $package, "profilepackages", $form);
        last unless $self->add_update_journal_item_hal($c,$hal);
        
        $guard->commit;

        if ('minimal' eq $preference) {
            $c->response->status(HTTP_NO_CONTENT);
            $c->response->header(Preference_Applied => 'return=minimal');
            $c->response->body(q());
        } else {
            #my $hal = $self->hal_from_profile($c, $package, $form);
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
        if ($c->user->roles eq "ccareadmin" || $c->user->roles eq "ccare") {
            $self->error($c, HTTP_FORBIDDEN, "Read-only resource for authenticated role");
            last;
        }

        last unless $self->valid_id($c, $id);
        my $package = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, profilepackage => $package);

        unless($package->get_column('contract_cnt') == 0) {
            $self->error($c, HTTP_LOCKED, "Cannot delete profile package that is still assigned to contracts");
            last;
        }
        unless($package->get_column('voucher_cnt') == 0) {
            $self->error($c, HTTP_LOCKED, "Cannot delete profile package that is assigned to vouchers");
            last;
        }
        
        last unless $self->add_delete_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            #my $_form = $self->get_form($c);
            return $self->hal_from_item($c, $package, "profilepackages"); });
        
        $package->delete;
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
