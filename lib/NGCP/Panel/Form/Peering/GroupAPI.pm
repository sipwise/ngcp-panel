package NGCP::Panel::Form::Peering::GroupAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'contract_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract used for this peering group.']
    },
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Peering group name.']
    },
);

has_field 'priority' => (
    type => 'IntRange',
    required => 0,
    range_start => '1',
    range_end => '9',
);

has_field 'time_set_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['By specifying a TimeSet the periods during which this group is active can be restricted.']
    },
);

has_field 'description' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Peering group description'],
    },
);


1;
# vim: set tabstop=4 expandtab:
