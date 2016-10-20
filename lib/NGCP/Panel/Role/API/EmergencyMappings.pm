package NGCP::Panel::Role::API::EmergencyMappings;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::EmergencyMapping::Mapping;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('emergency_mappings');
    if($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            'emergency_container.reseller_id' => $c->user->reseller_id,
        },{
            'join' => 'emergency_container',
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::EmergencyMapping::Mapping->new(ctx => $c);
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
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:emergencymappingcontainers', href => sprintf("/api/emergencymappingcontainers/%d", $item->emergency_container_id)),
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

    $resource{id} = int($item->id);
    $hal->resource({%resource});
    return $hal;
}

sub resource_from_item {
    my ($self, $c, $item) = @_;
    my $r = { $item->get_inflated_columns };
    return $r;
}

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    $resource->{lnp_provider_id} = delete $resource->{carrier_id};
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $container = $c->model('DB')->resultset('emergency_containers')->find($resource->{emergency_container_id});
    unless($container) {
        $c->log->error("invalid emergency container id '$$resource{emergency_container_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Emergency container id does not exist");
        return;
    }
    if ($old_resource->{code} ne $resource->{code} && $c->model('DB')->resultset('emergency_mappings')->search({
            emergency_container_id => $container->id,
            code => $resource->{code}
        },undef)->count > 0) {
        $c->log->error("Emergency mapping code '$$resource{code}' already exists for container id '$$resource{emergency_container_id}'");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "emergency mapping code already exists for emergency container");
        return;
    }

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
