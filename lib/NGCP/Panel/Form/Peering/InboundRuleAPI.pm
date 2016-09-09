package NGCP::Panel::Form::Peering::InboundRuleAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Peering::InboundRule';

has_field 'group_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The peering group this rule belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/group_id field pattern priority enabled reject_code reject_reason/],
);

1;
# vim: set tabstop=4 expandtab:
