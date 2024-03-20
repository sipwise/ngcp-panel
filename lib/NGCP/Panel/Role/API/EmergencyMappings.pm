package NGCP::Panel::Role::API::EmergencyMappings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);

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
    return NGCP::Panel::Form::get("NGCP::Panel::Form::EmergencyMapping::Mapping", $c);
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
            Data::HAL::Link->new(relation => 'self', href => sprintf("%s%d", $self->dispatch_path, $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:emergencymappingcontainers', href => sprintf("/api/emergencymappingcontainers/%d", $item->emergency_container_id)),
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

    $self->expand_fields($c, \%resource);
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
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Emergency container id does not exist",
                     "invalid emergency container id '$$resource{emergency_container_id}'");
        return;
    }
    if ($old_resource->{code} ne $resource->{code} && $c->model('DB')->resultset('emergency_mappings')->search({
            emergency_container_id => $container->id,
            code => $resource->{code}
        },undef)->count > 0) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "emergency mapping code already exists for emergency container",
                     "Emergency mapping code '$$resource{code}' already exists for container id '$$resource{emergency_container_id}'");
        return;
    }

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
