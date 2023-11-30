package NGCP::Panel::Form::Header::ConditionAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::Condition';

has_field 'rwr_dp' => (
    type => 'Select',
    options => [
        { value => '' },
        { value => 'caller_in' },
        { value => 'callee_in' },
        { value => 'caller_out' },
        { value => 'callee_out' },
    ],
    required => 0,
);

has_field 'rwr_set_id' => (
    type => 'PosInteger',
    required => 0,
);

has_field 'rule_id' => (
    type => 'PosInteger',
    required => 0,
);

has_field 'values' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of values.'],
    },
);

has_field 'values.condition_id' => (
    type => 'Hidden',
);

has_field 'values.value' => (
    type => 'Text',
    label => 'Source',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/match_type match_part match_name expression expression_negation value_type rule_id rwr_set_id rwr_dp enabled values/ ],
);

1;

# vim: set tabstop=4 expandtab:
