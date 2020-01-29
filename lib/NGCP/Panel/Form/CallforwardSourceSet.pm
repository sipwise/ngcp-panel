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
    element_attr => {
        rel => ['tooltip'],
        title => ['The unique name of the source set. Arbitrary text'],
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

has_field 'is_regex' => (
    type => 'Boolean',
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['A flag indicating, whether the numbers in this set are regular expressions. ' .
            'If true, all sources will be interpreted as perl compatible regular expressions and ' .
            'matched against the calling party number (in E164 format) of the calls. If false, the whole numbers ' .
            'are plainly matched while shell patterns like 431* or 49123~[1-5~]67 are possible. ' .
            'If true, capturing groups can be formed using parentheses and referenced in the ' .
            'destinations via \\1, \\2,... .'],
    },
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
    element_attr => {
        rel => ['tooltip'],
        title => ['The calling party number in E164 format to match. Regular expressions ' .
            'or shell patterns can be used depending on the is_regex flag. ' .
            'Use &quot;anonymous&quot; to match suppressed numbers.'],
    },
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
    render_list => [qw(name mode is_regex source source_add)],
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
