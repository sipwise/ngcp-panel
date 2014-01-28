package NGCP::Panel::Role::API::Subscribers;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use Try::Tiny;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::Subscriber::SubscriberAPI;
use NGCP::Panel::Utils::XMLDispatcher;
use NGCP::Panel::Utils::Prosody;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::Subscriber::SubscriberAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my $bill_resource = { $item->get_inflated_columns };
    my $prov_resource = { $item->provisioning_voip_subscriber->get_inflated_columns };
    my $customer = $self->get_customer($c, $item->contract_id);
    delete $prov_resource->{domain_id};
    delete $prov_resource->{account_id};
    my %resource = %{ $bill_resource->merge($prov_resource) };
    unless($customer->get_column('product_class') eq 'pbxaccount') {
        delete $resource{is_pbx_group};
        delete $resource{pbx_group_id};
    }

    my $hal = Data::HAL->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:subscriberpreferences', href => sprintf("/api/subscriberpreferences/%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:domains', href => sprintf("/api/domains/%d", $item->domain->id)),
            Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)),
            #Data::HAL::Link->new(relation => 'ngcp:registrations', href => sprintf("/api/registrations/%d", $item->contract->id)),
            #Data::HAL::Link->new(relation => 'ngcp:trustedsources', href => sprintf("/api/trustedsources/%d", $item->contract->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
    );

    $resource{customer_id} = int(delete $resource{contract_id});
    $resource{id} = int($item->id);
    $resource{domain} = $item->domain->domain;



    $hal->resource({%resource});
    return $hal;
}

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs;
    $item_rs = $c->model('DB')->resultset('voip_subscribers')
        ->search({ status => { '!=' => 'terminated' } });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        }, {
            join => { 'contract' => 'contact' },
        });
    }
    return $item_rs;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub get_customer {
    my ($self, $c, $customer_id) = @_;

    my $customer = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
    );
    $customer = $customer->search({
            'contact.reseller_id' => { '-not' => undef },
            'me.id' => $customer_id,
        },{
            join => 'contact'
        });
    $customer = $customer->search({
            '-or' => [
                'product.class' => 'sipaccount',
                'product.class' => 'pbxaccount',
            ],
        },{
            join => {'billing_mappings' => 'product' },
            '+select' => [ 'billing_mappings.id', 'product.class' ],
            '+as' => [ 'bmid', 'product_class' ],
        });
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $customer = $customer->search({
            'contact.reseller_id' => $c->user->reseller_id,
        });
    }
    $customer = $customer->first;
    unless($customer) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id', doesn't exist.");
        return;
    }
    return $customer;
}

sub get_billing_profile {
    my ($self, $c, $customer) = @_;

    my $mapping = $customer->billing_mappings->find($customer->get_column('bmid'));
    if($mapping) {
        return $mapping->billing_profile;
    } else {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid 'customer_id', doesn't have a valid billing mapping.");
        return;
    }
}

=pod
# you can't update a domain per se, only its preferences!
sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    $item->update($resource);

    return $item;
}
=cut

1;
# vim: set tabstop=4 expandtab:
