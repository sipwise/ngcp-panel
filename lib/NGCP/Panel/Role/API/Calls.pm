package NGCP::Panel::Role::API::Calls;
use Moose::Role;
use Sipwise::Base;
with 'NGCP::Panel::Role::API' => {
    -alias       =>{ item_rs  => '_item_rs', },
    -excludes    => [ 'item_rs' ],
};

use boolean qw(true);
use TryCatch;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Call::Admin;
use NGCP::Panel::Form::Call::Reseller;

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('cdr');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            -or => [
                { source_provider_id => $c->user->reseller->contract_id },
                { destination_provider_id => $c->user->reseller->contract_id },
            ],
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::Call::Admin->new;
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::Call::Reseller->new;
    }
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my $resource = $self->resource_from_item($c, $item, $form);

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
            # todo: customer can be in source_account_id or destination_account_id
#            Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->source_customer_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
        exceptions => [
            "source_provider_id", "destination_provider_id",
            "source_external_subscriber_id", "destination_external_subscriber_id",
            "source_external_contract_id", "destination_external_contract_id",
            "source_carrier_billing_fee_id", "destination_carrier_billing_fee_id",
            "source_reseller_billing_fee_id", "destination_reseller_billing_fee_id",
            "source_customer_billing_fee_id", "destination_customer_billing_fee_id",
            "source_carrier_billing_zone_id", "destination_carrier_billing_zone_id",
            "source_reseller_billing_zone_id", "destination_reseller_billing_zone_id",
            "source_customer_billing_zone_id", "destination_customer_billing_zone_id",
        ],
    );

    $resource->{id} = int($item->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item, $form) = @_;
    my $resource = { $item->get_inflated_columns };

    $resource->{source_customer_id} = delete $resource->{source_account_id};
    $resource->{destination_customer_id} = delete $resource->{destination_account_id};

    if($c->user->roles eq "reseller") {
        my @filter = ();
        if($item->source_provider_id ne "".$c->user->reseller->contract_id) {
            push @filter, (qw/
                source_user_id source_provider_id 
                source_external_subscriber_id source_external_contract_id
                source_customer_id source_ip
                source_reseller_cost source_customer_cost
                source_reseller_free_time source_customer_free_time
                source_customer_billing_fee_id source_customer_billing_zone_id
            /);
        }
        if($item->destination_provider_id ne "".$c->user->reseller->contract_id) {
            push @filter, (qw/
                destination_user_id destination_provider_id 
                destination_external_subscriber_id destination_external_contract_id
                destination_customer_id
                destination_reseller_cost destination_customer_cost
                destination_reseller_free_time destination_customer_free_time
                destination_customer_billing_fee_id destination_customer_billing_zone_id
            /);
        }
        for my $f(@filter) {
            $resource->{$f} = undef if exists($resource->{$f});
        }
    }

    return $resource;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
