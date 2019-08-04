package NGCP::Panel::Role::API::CustomerFraudEvents;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

sub _item_rs {
    my ($self, $c) = @_;

    my $interval = $c->request->param('interval') // '';
    my $notify_status = $c->request->param('notify_status') // '';

    my $item_rs = $c->model('DB')->resultset('contract_fraud_events')->search({
        $interval
            ? ('me.interval' => $interval)
            : (),
        $notify_status
            ? ('me.notify_status' => $notify_status)
            : ()
    });

    if($c->user->roles eq "admin") {
        #
    } elsif($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({ reseller_id => $c->user->reseller_id });
    }

    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CustomerFraudEvents::Admin", $c);
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::get("NGCP::Panel::Form::CustomerFraudEvents::Reseller", $c);
    }
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
            Data::HAL::Link->new(relation => 'collection', href => sprintf('/api/%s/', $self->resource_name)),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => \%resource,
        run => 0,
    );

    $resource{id} = int($item->id);
    $hal->resource({%resource});
    return $hal;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    my ($contract_id, $period, $period_date) = split(/-/, $id, 3);

    return $item_rs->search_rs({
        id => $contract_id,
        interval => $period,
        interval_date => $period_date
    })->first;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $cpc_rs = $c->model('DB')->resultset('cdr_period_costs')->search({
        contract_id => $item->id,
        period => $item->interval,
        period_date => $item->interval_date
    });
    my $cpc = $cpc_rs->first;
    unless ($cpc) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Customer fraud event does not exist");
        return;
    }

    # only update r/w fields
    $cpc->update({
        map { $_ => $resource->{$_} } qw(notify_status notified_at)
    });

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
