package NGCP::Panel::Form::Customer::PbxGroupBase;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw(form-horizontal)] }

with 'NGCP::Panel::Render::RepeatableJs';

has_field 'pbx_extension' => (
    type => 'Text',
    required => 1,
    label => 'Extension',
);

has_field 'pbx_hunt_policy' => (
    type => 'Select',
    required => 1,
    label => 'Hunting Policy',
    options => [
        { label => 'Serial Ringing', value => 'serial' },
        { label => 'Parallel Ringing', value => 'parallel' },
        { label => 'Random Ringing', value => 'random' },
        { label => 'Circular Ringing', value => 'circular' },
    ],
    default => 'serial',
);

has_field 'pbx_hunt_timeout' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    label => 'Hunting Timeout',
    default => 10,
);

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

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/pbx_extension pbx_hunt_policy pbx_hunt_timeout alias_number alias_number_add/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
