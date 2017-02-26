package NGCP::Panel::Role::API::PeeringInboundRules;
use NGCP::Panel::Utils::Generic qw(:all);

use strict;
use warnings;

use TryCatch;

use parent 'NGCP::Panel::Role::API';


use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Peering::InboundRuleAPI;
use NGCP::Panel::Utils::Peering;

sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('voip_peer_inbound_rules');
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Peering::InboundRuleAPI->new(ctx => $c);
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
            NGCP::Panel::Utils::DataHalLink->new(relation => 'ngcp:peeringgroups', href => sprintf("/api/peeringgroups/%d", $resource{group_id})),
        ],
        relation => 'ngcp:'.$self->resource_name,
    );

    $form //= $self->get_form($c);

    $self->validate_form(
        c => $c,
        resource => \%resource,
        form => $form,
        exceptions => [qw/group_id/],
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
        exceptions => [qw/group_id/],
    );
    unless($c->model('DB')->resultset('voip_peer_groups')->find($resource->{group_id})) {
        $c->log->error("peering group $$resource{group_id} does not exist");
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
        $c->log->error("peering rule already exists"); # TODO: user, message, trace, ...
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
        $c->log->error("peering rule priority $$resource{priority} already exists for this group");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering rule priority $$resource{priority} already exists for this group");
        return;
    }

    $item->update($resource);
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
