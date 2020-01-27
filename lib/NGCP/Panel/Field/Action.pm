package NGCP::Panel::Field::Action;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Repeatable';

has_field 'priority' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Header rule action priority, smaller value has the higher priority.'],
    },
);

has_field 'header' => (
    type => 'Text',
    label => 'Header',
    required => 1,
    id => 'c_header',
);

has_field 'header_part' => (
    type => 'Select',
    options => [
        { label => 'full', value => 'full' },
        { label => 'username', value => 'username' },
        { label => 'domain', value => 'domain' },
        { label => 'port', value => 'port' },
    ],
    label => 'Header Part',
    required => 1,
);

has_field 'action_type' => (
    type => 'Select',
    options => [
        { label => 'set', value => 'set' },
        { label => 'add', value => 'add' },
        { label => 'remove', value => 'remove' },
        { label => 'rsub', value => 'rsub' },
        { label => 'header', value => 'header' },
        { label => 'preference', value => 'preference' },
    ],
    label => 'Type',
    required => 1,
);

has_field 'value_part' => (
    type => 'Select',
    options => [
        { label => 'full', value => 'full' },
        { label => 'username', value => 'username' },
        { label => 'domain', value => 'domain' },
        { label => 'port', value => 'port' },
    ],
    label => 'Value Part',
    required => 1,
);

has_field 'value' => (
    type => 'Text',
    label => 'Value',
    required => 0,
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
        title => ['Enables or disables the action from being included in the headers processing logic'],
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/priority header header_part action_type value_part value rwr_set_id rwr_dp enabled/ ],
);

1;