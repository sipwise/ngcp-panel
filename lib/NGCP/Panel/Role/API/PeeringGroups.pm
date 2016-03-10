package NGCP::Panel::Role::API::PeeringGroups;

use Sipwise::Base;


use parent qw/NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Generic qw(:all);
use boolean qw(true);
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Peering::Group;
use NGCP::Panel::Utils::Peering;

sub item_name {
    return 'peeringgroup';
}

sub resource_name{
    return 'peeringgroups';
}

sub _item_rs {
    my($self, $c) = @_;
    return $c->model('DB')->resultset('voip_peer_groups');
}

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::Peering::Group->new;
}

sub check_duplicate {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_; 
    my $dup_item = $c->model('DB')->resultset('voip_peer_groups')->find({
        name => $resource->{name},
    });
    if($dup_item && (!$item || ($dup_item->id != $item->id) ) ) {
        $c->log->error("peering group with name '$$resource{name}' already exists"); # TODO: user, message, trace, ...
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Peering group with this name already exists");
        last;
    }
    return 1;
}

sub process_form_resource {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;
    $resource = $form->custom_get_values;
    return $resource;
}

sub process_hal_resource {
    my($self, $c, $item, $resource, $form) = @_;
    $resource->{contract_id} = delete $resource->{peering_contract_id};
    return $resource;
}

sub update {
    my ($self, $c, $item, $old_resource, $resource, $form) = @_;
    $item->update($resource);
    NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
    return $item;
}

1;
# vim: set tabstop=4 expandtab:
