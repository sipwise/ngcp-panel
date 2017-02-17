package NGCP::Panel::Role::API::PeeringGroups;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent 'NGCP::Panel::Role::API';

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Peering::Group;
use NGCP::Panel::Utils::Peering;

sub resource_name{return 'peeringgroups';}
sub dispatch_path{return '/api/peeringgroups/';}
sub relation{return 'http://purl.org/sipwise/ngcp-api/#rel-peeringgroups';}


sub _item_rs {
    my ($self, $c) = @_;
    my $item_rs = $c->model('DB')->resultset('voip_peer_groups');
    return $item_rs;
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Peering::Group->new(ctx => $c);
}

sub hal_from_item {
    my ($self, $c, $item, $form) = @_;
    my %resource = $item->get_inflated_columns;
    $resource{contract_id} = delete $resource{peering_contract_id};
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
            Data::HAL::Link->new(relation => 'ngcp:peeringservers', href => sprintf("/api/peeringservers/?group_id=%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:peeringrules', href => sprintf("/api/peeringrules/?group_id=%d", $item->id)),
            Data::HAL::Link->new(relation => 'ngcp:peeringinboundrules', href => sprintf("/api/peeringinboundrules/?group_id=%d", $item->id)),
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
    $resource = $form->custom_get_values;
    last unless $resource;

    my $dup_item = $c->model('DB')->resultset('voip_peer_groups')->find({
        name => $resource->{name},
    });
    if($dup_item && $dup_item->id != $item->id) {
        $c->log->error("peering group with name '$$resource{name}' already exists"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering group with this name already exists");
        return;
    }

    $item->update($resource);
    NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
