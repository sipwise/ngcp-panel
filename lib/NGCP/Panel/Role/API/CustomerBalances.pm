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
use NGCP::Panel::Form::Balance::CustomerBalance;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::DateTime;

sub item_rs {
    
    my ($self, $c, $include_terminated,$now) = @_;
    
    my $item_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
        include_terminated => (defined $include_terminated && $include_terminated ? 1 : 0),
        now => $now,
    );    

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
    return NGCP::Panel::Form::Balance::CustomerBalance->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    
    my %resource = $item->get_inflated_columns;
    $resource{cash_balance} /= 100.0;

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
            Data::HAL::Link->new(relation => 'ngcp:balanceintervals', href => sprintf("/api/balanceintervals/%d/%d", $item->contract->id, $item->id)),
            $self->get_journal_relation_link($item->contract->id),
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
    my ($self, $c, $id, $now) = @_;

    return NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
        contract => $self->item_rs($c)->find($id),
        now => $now);
        
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form, $now) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    $item = NGCP::Panel::Utils::ProfilePackages::underrun_update_balance(c => $c,
        balance => $item,
        now => $now,
        new_cash_balance => $resource->{cash_balance} * 100.0);
    
    $resource->{cash_balance} *= 100.0;
    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
