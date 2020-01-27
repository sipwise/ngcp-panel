package NGCP::Panel::Field::Condition;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Repeatable';

has_field 'match_type' => (
    type => 'Select',
    options => [
        { label => 'header', value => 'header' },
        { label => 'preference', value => 'preference' },
        { label => 'avp', value => 'avp' },
    ],
    label => 'Match',
    required => 1,
);

has_field 'match_part' => (
    type => 'Select',
    options => [
        { label => 'full', value => 'full' },
        { label => 'username', value => 'username' },
        { label => 'domain', value => 'domain' },
        { label => 'port', value => 'port' },
    ],
    label => 'Part',
    required => 1,
);

has_field 'match_name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
);

has_field 'expression' => (
    type => 'Select',
    options => [
        { label => 'is', value => 'is' },
        { label => 'contains', value => 'contains' },
        { label => 'matches', value => 'matches' },
        { label => 'regexp', value => 'regexp' },
    ],
    label => 'Expression',
    required => 1,
);

has_field 'expression_negation' => (
    type => 'Boolean',
    label => 'Not',
    default => 0,
);

has_field 'value_type' => (
    type => 'Select',
    options => [
        { label => 'input', value => 'input' },
        { label => 'preference', value => 'preference' },
        { label => 'avp', value => 'avp' },
    ],
    label => 'Type',
    required => 1,
);

has_field 'rwr_set_id' => (
    type => 'Hidden',
    required => 0,
);

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

has_field 'enabled' => (
    type => 'Boolean',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Enables or disables the condition from being included in the headers processing logic'],
    },
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
