package NGCP::Panel::Form::Peering::InboundRuleEdit;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Peering::InboundRule';

has_field 'group' => (
    type => '+NGCP::Panel::Field::PeeringGroupSelect',
    label => 'Peering Group',
    not_nullable => 1,
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['A peering group the rule belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/field pattern reject_code reject_reason enabled group/],
);

1;
# vim: set tabstop=4 expandtab:
