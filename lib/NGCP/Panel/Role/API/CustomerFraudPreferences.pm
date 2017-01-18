package NGCP::Panel::Role::API::CustomerFraudPreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::CustomerFraudPreferences::PreferencesAPI;
use NGCP::Panel::Utils::Contract qw();

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::CustomerFraudPreferences::PreferencesAPI->new;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;

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

    delete $resource{id};
    delete $resource{contract_id};
    $hal->resource({%resource});
    return $hal;
}

sub _item_rs {

    my ($self, $c, $include_terminated) = @_;

    my $customer_rs = $c->model('DB')->resultset('contracts')->search({
        $include_terminated ? () : ('me.status' => { '!=' => 'terminated' }),
    }, {
        join => 'contact',
        alias => 'me',
    });
    if($c->user->roles eq "admin") {
        $customer_rs = $customer_rs->search({
            'contact.reseller_id' => { '-not' => undef },
        });
    } elsif($c->user->roles eq "reseller") {
        $customer_rs = $customer_rs->search({
            'contact.reseller_id' => $c->user->reseller_id,
        });
    }
    return $customer_rs;

}

sub item_by_id {
    my ($self, $c, $id, $customer, $include_terminated) = @_;

    my $item = $c->model('DB')->resultset('contract_fraud_preferences')->find({ contract_id => $id });
    unless ($item) {
        $customer //= $self->_item_rs($c,$include_terminated)->find($id);
        if ($customer) {
            $item = $c->model('DB')->resultset('contract_fraud_preferences')->new_result({
                contract_id => $id,
                fraud_interval_limit => undef,
                fraud_interval_lock => undef,
                fraud_interval_notify => undef,
                fraud_daily_limit => undef,
                fraud_daily_lock => undef,
                fraud_daily_notify => undef,
            });
        }
    }

    return $item;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    delete $resource->{id};
    my $schema = $c->model('DB');

    $form //= $self->get_form($c);

    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    $resource->{contract_id} = $item->contract->id;

    foreach my $type (qw(interval daily)) {
        if (not defined $resource->{'fraud_'.$type.'_limit'}) {
            if (defined $resource->{'fraud_'.$type.'_lock'}) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'for cleared fraud_'.$type.'_limit, fraud_'.$type.'_lock must be cleared too.');
                return;
            }
            if (defined $resource->{'fraud_'.$type.'_notify'}) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 'for cleared fraud_'.$type.'_limit, fraud_'.$type.'_notify must be cleared too.');
                return;
            }
        }
    }

    try {
        $item = $c->model('DB')->resultset('contract_fraud_preferences')->update_or_create($resource,{
            key => 'contract_id'
        });
        $item->discard_changes;
    } catch($e) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to set customer fraud preference: $e");
        return;
    };

    return $item;
}

1;
