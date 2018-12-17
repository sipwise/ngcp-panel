package NGCP::Panel::Form::Header::RuleAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::Rule';

has_field 'set_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Header rule set id, one the rule must belong to.'],
    },
);

has_field 'priority' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Header rule priority, smaller value has the higher priority.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/name direction description stopper enabled set_id priority/],
);

1;

# vim: set tabstop=4 expandtab:
