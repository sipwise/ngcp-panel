package NGCP::Panel::Role::API::BalanceIntervals;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Balance::BalanceIntervalAPI;
use NGCP::Panel::Utils::Contract;
use NGCP::Panel::Utils::ProfilePackages qw();
use NGCP::Panel::Utils::DateTime;

sub _contract_rs {
    
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
    
    #my $item_rs = $c->model('DB')->resultset('contract_balances');
    #if($c->user->roles eq "admin") {
    #} elsif($c->user->roles eq "reseller") {
    #    $item_rs = $item_rs->search({ 
    #        'contact.reseller_id' => $c->user->reseller_id
    #    },{
    #        join => { contract => 'contact' },
    #    });
    #}
    #return $item_rs;
}

sub _item_rs {
    
    my $self = shift;
    return $self->_contract_rs(@_);
    
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Balance::BalanceIntervalAPI->new;
}

sub hal_from_balance {
    my ($self, $c, $item, $form, $now, $use_root_collection_link) = @_;
    
    my $contract = $item->contract;
    my $is_customer = (defined $contract->contact->reseller_id ? 1 : 0);
    my $bm_start = NGCP::Panel::Utils::ProfilePackages::get_actual_billing_mapping(c => $c, contract => $contract, now => $item->start);
    my $profile_at_start = $bm_start->billing_mappings->first->billing_profile;
    my $is_actual = NGCP::Panel::Utils::DateTime::is_infinite_future($item->end) || NGCP::Panel::Utils::DateTime::set_local_tz($item->end) >= $now;
    my ($is_timely,$timely_start,$timely_end) = NGCP::Panel::Utils::ProfilePackages::get_timely_range(
        package => $contract->profile_package,
        contract => $contract,
        balance => $item,
        now => $now);
    my $notopup_expiration = undef;
    $notopup_expiration = NGCP::Panel::Utils::ProfilePackages::get_notopup_expiration(
        package => $contract->profile_package,
        contract => $contract,
        balance => $item) if $is_actual;          
    #my $invoice = $item->invoice;
    
    my %resource = $item->get_inflated_columns;
    $resource{cash_balance} /= 100.0;
    $resource{cash_debit} = (delete $resource{cash_balance_interval}) / 100.0;
    $resource{free_time_spent} = delete $resource{free_time_balance_interval};
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );
    $resource{start} = delete $resource{start};
    $resource{stop} = delete $resource{end};
    $resource{start} = $datetime_fmt->format_datetime($resource{start}) if defined $resource{start};
    $resource{stop} = $datetime_fmt->format_datetime($resource{stop}) if defined $resource{stop};
    
    $resource{billing_profile_id} = $profile_at_start->id;

    $resource{timely_topup_start} = (defined $timely_start ? $datetime_fmt->format_datetime($timely_start) : undef);
    $resource{timely_topup_stop} = (defined $timely_end ? $datetime_fmt->format_datetime($timely_end) : undef);
    
    $resource{notopup_discard_expiry} = (defined $notopup_expiration ? $datetime_fmt->format_datetime($notopup_expiration) : undef);
    
    $resource{is_actual} = $is_actual;
    
    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            ($use_root_collection_link ? Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)) :
                Data::HAL::Link->new(relation => 'collection', href => sprintf("/api/%s/%d/", $self->resource_name, $contract->id)) ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("/api/%s/%d/%d", $self->resource_name, $contract->id, $item->id)),
            ($is_customer ? ( Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $contract->id)),
                Data::HAL::Link->new(relation => 'ngcp:customerbalances', href => sprintf("/api/customerbalances/%d", $contract->id)) ) :
                Data::HAL::Link->new(relation => 'ngcp:contracts', href => sprintf("/api/contracts/%d", $contract->id)) ),
            Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $profile_at_start->id)),
            #($invoice ? Data::HAL::Link->new(relation => 'ngcp:invoices', href => sprintf("/api/invoices/%d", $invoice->id)) : ()),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
        exceptions => [ 'billing_profile_id', 'invoice_id' ],
    );

    #$resource{id} = int($item->contract->id);
    $hal->resource({%resource});
    return $hal;
}

sub contract_by_id {
    my ($self, $c, $id) = @_;

    return $self->_contract_rs($c)->find($id); #must not process item controller's query params

}

sub balances_rs {
    my ($self, $c, $contract, $now) = @_;
    
    $now //= NGCP::Panel::Utils::DateTime::current_local;
    NGCP::Panel::Utils::ProfilePackages::catchup_contract_balances(c => $c,
        contract => $contract,
        now => $now);
    
    return $self->apply_query_params($c,$self->can('query_params') ? $self->query_params : {},$contract->contract_balances);
    
}

sub balance_by_id {
    my ($self, $c, $contract, $id, $now) = @_;

    $now //= NGCP::Panel::Utils::DateTime::current_local;
    my $balance = NGCP::Panel::Utils::ProfilePackages::catchup_contract_balances(c => $c,
        contract => $contract,
        now => $now);
    
    if (defined $id) {
        $balance = $contract->contract_balances->find($id);
    }
    return $balance;
    
}

1;
