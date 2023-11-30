package NGCP::Panel::Form::Header::ActionAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Header::Action';

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

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/rule_id priority header header_part action_type value_part value rwr_set_id rwr_dp enabled/ ],
);

1;

# vim: set tabstop=4 expandtab:
