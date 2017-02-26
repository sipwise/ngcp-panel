package NGCP::Panel::Role::API::NcosLnpCarriers;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::NCOS::LnpAPI;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('ncos_lnp_list');
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::NCOS::LnpAPI->new(ctx => $c);
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
            NGCP::Panel::Utils::DataHalLink->new(relation => 'collection', href => sprintf("/api/%s/", $self->resource_name)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:ncoslevels', href => sprintf("/api/ncoslevels/%d", $item->ncos_level_id)),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        run => 0,
        exceptions => [qw/ncos_level_id/],
    );

    $resource{id} = int($item->id);
    $resource{carrier_id} = int($item->lnp_provider_id);
    delete $resource{lnp_provider_id};
    $hal->resource({%resource});
    return $hal;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub resource_from_item {
    my ($self, $c, $item) = @_;
    my $r = { $item->get_inflated_columns };
    $r->{carrier_id} = delete $r->{lnp_provider_id};
    return $r;
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    $resource->{lnp_provider_id} = delete $resource->{carrier_id};
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
        exceptions => [qw/ncos_level_id/],
    );

    my $level = $c->model('DB')->resultset('ncos_levels')->find(
        $resource->{ncos_level_id},
    );
    unless($level) {
        $c->log->error("invalid ncos_level_id '$$resource{ncos_level_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid ncos_level_id, level does not exist");
        return;
    }

    my $dup_item = $level->ncos_lnp_lists->search({
        lnp_provider_id => $resource->{lnp_provider_id},
    })->first;
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("ncos lnp carrier '$$resource{lnp_provider_id}' already exists for ncos_level_id '$$resource{ncos_level_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "NCOS lnp entry already exists for given ncos level");
        return;
    }

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
