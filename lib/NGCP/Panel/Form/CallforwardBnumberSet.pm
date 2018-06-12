package NGCP::Panel::Form::CallforwardBnumberSet;
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
    element_attr => {
        rel => ['tooltip'],
        title => ['The unique name of the B-Number set. Arbitrary text'],
    },
);

has_field 'mode' => (
    type => 'Select',
    options => [
        {value => 'whitelist', label => 'whitelist'},
        {value => 'blacklist', label => 'blacklist'},
    ],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The source set mode']
    },
);

has_field 'bnumbers' => (
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

has_field 'bnumbers.id' => (
    type => 'Hidden',
);

has_field 'bnumbers.number' => (
    type => 'Text',  # +NGCP::Panel::Field::URI
    label => 'B-Number',
    required => 1,
    do_label => 1,
    wrapper_class => [qw/hfh-rep-field/],
    element_attr => {
        rel => ['tooltip'],
        title => ['Matches the B-Number (original number dialled by the caller) in E164 format. ' .
            'Shell patterns like 431* or 49123~[1-5~]67 are possible. ' .
            'Use &quot;anonymous&quot; to match suppressed numbers.'],
    },
);

has_field 'bnumbers.rm' => (
    type => 'RmElement',
    value => 'Remove',
    element_class => [qw/btn btn-primary pull-right/],
#    tags => {
#        "data-confirm" => "Delete",
#    },
);

has_field 'bnumber_add' => (
    type => 'AddElement',
    repeatable => 'bnumbers',
    value => 'Add another B-Number',
    element_class => [qw/btn btn-primary pull-right/],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(name mode bnumbers bnumber_add)],
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
