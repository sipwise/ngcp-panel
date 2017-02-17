package NGCP::Panel::Role::API::EmergencyMappingContainers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::EmergencyMapping::Container;
use NGCP::Panel::Form::EmergencyMapping::ContainerAdmin;

sub _item_rs {
    my ($self, $c) = @_;

    my $item_rs = $c->model('DB')->resultset('emergency_containers');
    if($c->user->roles eq "reseller") {
        $item_rs = $item_rs->search({
            reseller_id => $c->user->reseller_id,
        });
    }
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    my $form;
    
    if($c->user->roles eq "reseller") {
        $form = NGCP::Panel::Form::EmergencyMapping::Container->new(ctx => $c);
    } else {
        $form = NGCP::Panel::Form::EmergencyMapping::ContainerAdmin->new(ctx => $c);
    }
    return $form;
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;

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
            Data::HAL::Link->new(relation => 'ngcp:emergencymappings', href => sprintf("/api/emergencymappings/?emergency_container_id=%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:reseller', href => sprintf("/api/resellers/%d", $item->reseller_id)),
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

sub item_by_id {
    my ($self, $c, $id) = @_;
    my $item_rs = $self->item_rs($c);
    return $item_rs->find($id);
}

sub update_item {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;

    $form //= $self->get_form($c);
    return unless $self->validate_form(
        c => $c,
        form => $form,
        resource => $resource,
    );

    my $reseller_item = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
    unless($reseller_item) {
        $c->log->error("reseller id '$$resource{reseller_id}' does not exist");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Reseller id does not exist");
        return;
    }

    my $dup_item = $c->model('DB')->resultset('emergency_containers')->find({
        reseller_id => $resource->{reseller_id},
        name => $resource->{name},
    });
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("emergency mapping container with name '$$resource{name}' already exists for this reseller");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Emergency mapping container with this name already exists for this reseller");
        return;
    }

    $item->update($resource);

    return $item;
}

1;
# vim: set tabstop=4 expandtab:
