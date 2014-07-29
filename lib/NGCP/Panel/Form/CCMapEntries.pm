package NGCP::Panel::Form::CCMapEntries;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;


with 'NGCP::Panel::Render::RepeatableJs';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {return [qw/submitid fields actions/]}
sub build_form_element_class {return [qw/form-horizontal/] }

has_field 'subscriber_id' => (
    type => 'Hidden',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber ID.'],
    },
);

has_field 'mappings' => (
    type => 'Repeatable',
    required => 1,
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    tags => { 
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
    element_attr => {
        rel => ['tooltip'],
        title => ['An Array of mappings, each entry containing the mandatory key "auth_key".'],
    },
);

has_field 'mappings.id' => (
    type => 'Hidden',
);

has_field 'mappings.source_uuid' => (
    type => 'Hidden',
);

has_field 'mappings.auth_key' => (
    type => 'Text',
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'mappings.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
);


has_field 'mappings_add' => (
    type => 'AddElement',
    repeatable => 'mappings',
    value => 'Add another Mapping',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(mappings mappings_add)],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

1;

# vim: set tabstop=4 expandtab:
