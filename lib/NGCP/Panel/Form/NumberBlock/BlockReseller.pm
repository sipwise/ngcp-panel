package NGCP::Panel::Form::NumberBlock::BlockReseller;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'e164' => (
    type => '+NGCP::Panel::Field::E164Range',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The E164 number block.'],
    },
    label => 'Number Block',
    do_label => 1,
    do_wrapper => 1,
    wrapper_class => [qw/hfh-rep-field/],

);

has_field 'allocable' => (
    type => 'Boolean',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Allow numbers to be allocated from this block.'],
    },
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
    render_list => [qw/e164 allocable/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
