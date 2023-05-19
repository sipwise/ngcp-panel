package NGCP::Panel::Form::Customer::PbxGroupEdit;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Customer::PbxGroupBase';

has_field 'alias_number' => (
    type => '+NGCP::Panel::Field::AliasNumber',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'alias_number_add' => (
    type => 'AddElement',
    repeatable => 'alias_number',
    value => 'Add another number',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/pbx_extension pbx_hunt_policy pbx_hunt_timeout pbx_hunt_cancel_mode alias_number alias_number_add/],
);

1;
# vim: set tabstop=4 expandtab:
