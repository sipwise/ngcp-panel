package NGCP::Panel::Role::API::PeeringInboundRules;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Peering;

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('voip_peer_inbound_rules');
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::Peering::InboundRuleAPI", $c);
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
            Data::HAL::Link->new(relation => 'ngcp:peeringgroups', href => sprintf("/api/peeringgroups/%d", $resource{group_id})),
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
    unless($c->model('DB')->resultset('voip_peer_groups')->find($resource->{group_id})) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering group $$resource{group_id} does not exist");
        return;
    }
    my $dup_item = $c->model('DB')->resultset('voip_peer_inbound_rules')->find({
        group_id => $resource->{group_id},
        field => $resource->{field},
        pattern => $resource->{pattern},
        reject_code => $resource->{reject_code},
        reject_reason => $resource->{reject_reason},
        enabled => $resource->{enabled},
        priority => $resource->{priority},
    });
    if($dup_item && $dup_item->id != $item->id) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering rule already exists");
        return;
    }
    if($c->model('DB')->resultset('voip_peer_inbound_rules')->search({
            id => { '!=' => $item->id },
            group_id => $resource->{group_id},
            priority => $resource->{priority},
        },
        {}
    )->count) {
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering rule priority $$resource{priority} already exists for this group");
        return;
    }

    $item->update($resource);
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
