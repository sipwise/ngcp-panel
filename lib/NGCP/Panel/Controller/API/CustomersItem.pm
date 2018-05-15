package NGCP::Panel::Controller::API::CustomersItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::Contract qw();
use NGCP::Panel::Utils::BillingMappings qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Customers/;

sub resource_name{
    return 'customers';
}

sub dispatch_path{
    return '/api/customers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customers';
}

sub journal_query_params {
    my($self,$query_params) = @_;
    return $self->get_journal_query_params($query_params);
}

__PACKAGE__->set_config({
    allowed_roles => {
        Default => [qw/admin reseller subscriberadmin/],
        Journal => [qw/admin reseller/],
    }
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        if($c->user->roles eq "subscriberadmin") {
            unless($c->user->account_id == $id) {
                $self->error($c, HTTP_FORBIDDEN, "Invalid customer id");
                return;
            }
        }
        last unless $self->valid_id($c, $id);
        my $customer = $self->customer_by_id($c, $id);
        last unless $self->resource_exists($c, customer => $customer);

        my $hal = $self->hal_from_customer($c, $customer, undef, NGCP::Panel::Utils::DateTime::current_local);
        $guard->commit; #potential db write ops in hal_from

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
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
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

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $customer = $self->customer_by_id($c, $id, $now);
        last unless $self->resource_exists($c, customer => $customer);

        my $old_resource = { $customer->get_inflated_columns };
        delete $old_resource->{profile_package_id};
        my $billing_mapping = NGCP::Panel::Utils::BillingMappings::get_actual_billing_mapping(c => $c, now => $now, contract => $customer, );
        #my $billing_mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
        $old_resource->{billing_profile_id} = $billing_mapping->billing_profile_id;
        $old_resource->{billing_profile_definition} = undef;

        my $resource = $self->apply_patch($c, $old_resource, $json, sub {
            my ($missing_field,$entity) = @_;
            if ($missing_field eq 'billing_profiles') {
                $entity->{billing_profiles} = NGCP::Panel::Utils::BillingMappings::resource_from_future_mappings($customer);
                $entity->{billing_profile_definition} //= 'profiles';
            } elsif ($missing_field eq 'profile_package_id') {
                $entity->{profile_package_id} = $customer->profile_package_id;
                $entity->{billing_profile_definition} //= 'package';
            }
        });
        last unless $resource;

        my $form = $self->get_form($c);
        $customer = $self->update_customer($c, $customer, $old_resource, $resource, $form, $now);
        last unless $customer;

        my $hal = $self->hal_from_customer($c, $customer, $form, $now);
        last unless $self->add_update_journal_item_hal($c, $hal);

        $guard->commit;

        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

sub PUT :Allow {
    my ($self, $c, $id) = @_;
    $c->model('DB')->set_transaction_isolation('READ COMMITTED');
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $preference = $self->require_preference($c);
        last unless $preference;

        my $now = NGCP::Panel::Utils::DateTime::current_local;
        my $customer = $self->customer_by_id($c, $id, $now);
        last unless $self->resource_exists($c, customer => $customer);
        my $resource = $self->get_valid_put_data(
            c => $c,
            id => $id,
            media_type => 'application/json',
        );
        last unless $resource;
        my $old_resource = { $customer->get_inflated_columns };

        my $form = $self->get_form($c);
        $customer = $self->update_customer($c, $customer, $old_resource, $resource, $form, $now);
        last unless $customer;

        my $hal = $self->hal_from_customer($c, $customer, $form,$now);
        last unless $self->add_update_journal_item_hal($c,$hal);

        $guard->commit;

        $self->return_representation($c, 'hal' => $hal, 'preference' => $preference );
    }
    return;
}

=pod
# we don't allow to delete customers
sub DELETE :Allow {
    my ($self, $c, $id) = @_;
    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $customer = $self->customer_by_id($c, $id);
        last unless $self->resource_exists($c, customer => $customer);

        # TODO: do we want to prevent deleting used customers?
        #my $customer_count = $c->model('DB')->resultset('customers')->search({
        #    contact_id => $id
        #});
        #if($customer_count > 0) {
        #    $self->error($c, HTTP_LOCKED, "Contact is still in use.");
        #    last;
        #} else {
            $customer->delete;
        #}
        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}
=cut

sub get_journal_methods{
    return [qw/handle_item_base_journal handle_journals_get handle_journalsitem_get handle_journals_options handle_journalsitem_options handle_journals_head handle_journalsitem_head/];
}

1;

__END__

=head1 NAME

NGCP::Panel::Controller::API::CustomersItem

=head1 DESCRIPTION

A helper to manipulate the customers data via API

=head1 AUTHOR

Sipwise Development Team

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

# vim: set tabstop=4 expandtab:
