package NGCP::Panel::Form::CallforwardSourceSet;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => (default => 'Bootstrap');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    wrapper_class => [qw/hfh-rep-field/],
    required => 1,
);

has_field 'source' => (
    type => 'Repeatable',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 0,
    required => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep/],
);

has_field 'source.id' => (
    type => 'Hidden',
);

has_field 'source.source' => (
    type => 'Text',  # +NGCP::Panel::Field::URI
    label => 'Source',
    required => 1,
    do_label => 1,
    wrapper_class => [qw/hfh-rep-field/],
);

has_field 'source.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
#    tags => {
#        "data-confirm" => "Delete",
#    },
);

has_field 'source_add' => (
    type => 'AddElement',
    repeatable => 'source',
    value => 'Add another source',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(name source source_add)],
);

has_field 'save' => (
    type => 'Submit',
    do_label => 0,
    value => 'Save',
    element_class => [qw(btn btn-primary)],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw(modal-footer)],
    render_list => [qw(save)],
);

1;

# vim: set tabstop=4 expandtab:
