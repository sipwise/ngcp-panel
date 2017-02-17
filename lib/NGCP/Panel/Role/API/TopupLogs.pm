package NGCP::Panel::Role::API::TopupLogs;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Topup::Log;
use Data::Dumper;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('topup_logs');
    if($c->user->roles eq "admin") {
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        },{
            join => { 'contract' => 'contact' },
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Topup::Log->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;
    
    my $datetime_fmt = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    );
    $resource{timestamp} = $datetime_fmt->format_datetime($resource{timestamp}) if defined $resource{timestamp};
    $resource{amount} = $resource{amount} / 100.0 if defined $resource{amount};
    $resource{cash_balance_before} = $resource{cash_balance_before} / 100.0 if defined $resource{cash_balance_before};
    $resource{cash_balance_after} = $resource{cash_balance_after} / 100.0 if defined $resource{cash_balance_after};
    
    my $hal = NGCP::Panel::Utils::DataHal->new(
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
            (defined $item->subscriber_id ? Data::HAL::Link->new(relation => 'ngcp:subscribers', href => sprintf("/api/subscribers/%d", $item->subscriber_id)) : ()),
            (defined $item->contract_id ? Data::HAL::Link->new(relation => 'ngcp:customers', href => sprintf("/api/customers/%d", $item->contract_id)) : ()),
            (defined $item->voucher_id ? Data::HAL::Link->new(relation => 'ngcp:vouchers', href => sprintf("/api/vouchers/%d", $item->voucher_id)) : ()),
             
            (defined $item->profile_before_id ? Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $item->profile_before_id)) : ()),
            (defined $item->profile_after_id ? Data::HAL::Link->new(relation => 'ngcp:billingprofiles', href => sprintf("/api/billingprofiles/%d", $item->profile_after_id)) : ()),
            
            (defined $item->package_before_id ? Data::HAL::Link->new(relation => 'ngcp:profilepackages', href => sprintf("/api/profilepackages/%d", $item->package_before_id)) : ()),
            (defined $item->package_after_id ? Data::HAL::Link->new(relation => 'ngcp:profilepackages', href => sprintf("/api/profilepackages/%d", $item->package_after_id)) : ()),
            
            (defined $item->contract_balance_before_id ? Data::HAL::Link->new(relation => 'ngcp:balanceintervals', href => sprintf("/api/balanceintervals/%d/%d", $item->contract_id, $item->contract_balance_before_id)) : ()),
            (defined $item->contract_balance_after_id ? Data::HAL::Link->new(relation => 'ngcp:balanceintervals', href => sprintf("/api/balanceintervals/%d/%d", $item->contract_id, $item->contract_balance_after_id)) : ()),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
        exceptions => [qw/id subscriber_id contract_id voucher_id package_before_id package_after_id profile_before_id profile_after_id contract_balance_before_id contract_balance_after_id/],
    );

    $resource{id} = int($item->id);
    $hal->resource({%resource});
    return $hal;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

1;
