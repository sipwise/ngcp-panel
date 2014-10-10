package NGCP::Panel::Role::API::CustomerBalances;
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
use NGCP::Panel::Form::CustomerBalance;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::DateTime;

sub item_rs {
    my ($self, $c) = @_;

    my $item_rs = NGCP::Panel::Utils::Contract::get_customer_rs(c => $c);
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ 
            'contact.reseller_id' => $c->user->reseller_id
        },{
            join => 'contact',
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::CustomerBalance->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;
    $resource{cash_balance} /= 100;

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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->contract->id)),
            Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract->id)),
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

    $resource{id} = int($item->contract->id);
    $hal->resource({%resource});
    return $hal;
}

sub item_by_id {
    my ($self, $c, $id) = @_;

    my $stime = NGCP::Panel::Utils::DateTime::current_local()->truncate(to => 'month');
    my $etime = $stime->clone->add(months => 1)->subtract(seconds => 1);
  
    my $item_rs = $self->item_rs($c);
    $item_rs = $item_rs
        ->search({
            'me.id' => $id,
        },{
            '+select' => 'billing_mappings.id',
            '+as' => 'bmid',
        });


    my $item = $item_rs->first;
    my $billing_mapping = $item->billing_mappings->find($item->get_column('bmid'));

    my $balance = NGCP::Panel::Utils::Contract::get_contract_balance(
        c => $c,
        contract => $item,
        profile => $billing_mapping->billing_profile,
        stime => $stime,
        etime => $etime,
    );

    return $balance;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    $resource->{cash_balance} *= 100;
    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
