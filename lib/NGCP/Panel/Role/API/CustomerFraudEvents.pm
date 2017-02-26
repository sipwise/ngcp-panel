package NGCP::Panel::Role::API::CustomerFraudEvents;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';
use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::CustomerFraudEvents::Admin;
use NGCP::Panel::Form::CustomerFraudEvents::Reseller;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('contract_fraud_events')->search(
        undef,
        {
            bind => [ $c->request->param('interval') || 'month' ]
        }
    );

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
        return NGCP::Panel::Form::CustomerFraudEvents::Admin->new;
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::CustomerFraudEvents::Reseller->new;
    }
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;

    my %resource = $item->get_inflated_columns;

    my $hal = NGCP::Panel::Utils::DataHal->new(
        links => [
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf('/api/%s/', $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
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
    return $item_rs->find($id);
}

1;
# vim: set tabstop=4 expandtab:
