package NGCP::Panel::Role::API::CustomerBalances;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::DateTime;

sub _item_rs {

    my ($self, $c, $include_terminated,$now) = @_;

    my $item_rs = NGCP::Panel::Utils::Contract::get_contract_rs(
        schema => $c->model('DB'),
        include_terminated => (defined $include_terminated && $include_terminated ? 1 : 0),
        now => $now,
    );

    if($c->user->roles eq "admin" || $c->user->roles eq "ccareadmin") {
    } elsif($c->user->roles eq "reseller" || $c->user->roles eq "ccare") {
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
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Balance::CustomerBalanceAPI", $c);
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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->contract->id)),
            Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract->id)),
            Data::HAL::Link->new(relation => 'ngcp:balanceintervals', href => sprintf("/api/balanceintervals/%d/%d", $item->contract->id, $item->id)),
            $self->get_journal_relation_link($c, $item->contract->id),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => $resource,
        form => $form,
        run => 0,
    );

    $resource->{id} = int($item->contract->id);
    $hal->resource($resource);
    return $hal;
}

sub resource_from_item{
    my($self, $c, $item) = @_;
    my %resource = $item->get_inflated_columns;
    #$resource{cash_balance} /= 100.0;
    ##$resource{cash_balance_interval} /= 100.0;
    $resource{cash_balance} /= 100.0;
    $resource{cash_debit} = (delete $resource{cash_balance_interval}) / 100.0;
    $resource{free_time_spent} = delete $resource{free_time_balance_interval};

    my $contract_create = NGCP::Panel::Utils::DateTime::set_local_tz($item->contract->create_timestamp // $item->contract->modify_timestamp);
    if (NGCP::Panel::Utils::DateTime::set_local_tz($item->start) <= $contract_create && (NGCP::Panel::Utils::DateTime::is_infinite_future($item->end) || NGCP::Panel::Utils::DateTime::set_local_tz($item->end) >= $contract_create)) {
        $resource{ratio} = NGCP::Panel::Utils::ProfilePackages::get_free_ratio($contract_create,NGCP::Panel::Utils::DateTime::set_local_tz($item->start),NGCP::Panel::Utils::DateTime::set_local_tz($item->end));
        #to avoid PUT error in API:
        ##   Failed test 'customerbalances: check_get2put: check put successful (Unprocessable Entity: Validation failed. field='ratio', input='0.35483871', errors='Total size of number must be less than or equal to 8, but is 9')'
        ##   Failed test 'customerbalances: check_get2put: check put successful (Unprocessable Entity: Validation failed. field='ratio', input='0.3548387', errors='May have a maximum of 2 digits after the decimal point, but has 7')'

        #$resource{ratio} = sprintf("%.2f", $resource{ratio});

        # any readonly field is now removed before validation, see below.

    } else {
        $resource{ratio} = 1.0;
    }
    return \%resource;
}

sub item_by_id {
    my ($self, $c, $id, $now) = @_;

    return NGCP::Panel::Utils::ProfilePackages::get_contract_balance(c => $c,
        contract => $self->item_rs($c)->find($id),
        now => $now);

}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form, $now) = @_;

    # remove any readonly field before validation:
    my %ro_fields = map { $_ => 1; } keys %$resource;
    $ro_fields{cash_balance} = 0;
    $ro_fields{free_time_balance} = 0;
    foreach my $field (keys %$resource) {
        delete $resource->{$field} if $ro_fields{$field};
    }

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $entities = { contract => $item->contract, };
    my $log_vals = {};
    $item = NGCP::Panel::Utils::ProfilePackages::set_contract_balance(
        c => $c,
        balance => $item,
        cash_balance => $resource->{cash_balance} * 100.0,
        free_time_balance => $resource->{free_time_balance},
        now => $now,
        log_vals => $log_vals);

    my $topup_log = NGCP::Panel::Utils::ProfilePackages::create_topup_log_record(
        c => $c,
        now => $now,
        entities => $entities,
        log_vals => $log_vals,
        request_token => NGCP::Panel::Utils::ProfilePackages::API_DEFAULT_TOPUP_REQUEST_TOKEN,
    );

    $item->discard_changes;

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
