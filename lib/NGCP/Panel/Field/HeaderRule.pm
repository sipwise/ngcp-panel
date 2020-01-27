package NGCP::Panel::Field::HeaderRule;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Repeatable';

has_field 'name' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'priority' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Header rule priority, smaller value has the higher priority.'],
    },
);

has_field 'direction' => (
    type => 'Select',
    options => [
        { label => 'Inbound', value => 'inbound' },
        { label => 'Local', value => 'local' },
        { label => 'Peer', value => 'peer' },
        { label => 'Outbound', value => 'outbound' },
        { label => 'Call Forward Inbound', value => 'cf_inbound' },
        { label => 'Call Forward Outbound', value => 'cf_outbound' },
        { label => 'Reply', value => 'reply' },
    ],
    label => 'Direction',
    required => 1,
);

has_field 'description' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'stopper' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Controls whether next rule is processed if the current one fails.'],
    },
);

has_field 'enabled' => (
    type => 'Boolean',
    default => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Enables or disables the rule from being included in the headers processing logic'],
    },
);

has_field 'actions' => (
    type => '+NGCP::Panel::Field::Action',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The list of actions in the rule.'],
    },
);

has_field 'conditions' => (
    type => '+NGCP::Panel::Field::Condition',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The list of conditions in the rule.'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/priority name direction description stopper enabled actions conditions/],
);

no Moose;
1;

# vim: set tabstop=4 expandtab:
