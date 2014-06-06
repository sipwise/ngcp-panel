package NGCP::Panel::Form::Invoice::Invoice;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'template' => (
    type => '+NGCP::Panel::Field::InvoiceTemplate',
    label => 'Invoice Template',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The invoice template to use for the invoice generation.']
    },
);

has_field 'contract' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    label => 'Customer',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract to create the invoice for.']
    },
);

has_field 'period' => (
    #type => '+NGCP::Panel::Field::DateTime',
    type => '+NGCP::Panel::Field::MonthPicker',
    element_attr => {
        rel => ['tooltip'],
        title => ['YYYY-MM']
    },
    label => 'Invoice Period',
    required => 1,
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
    render_list => [qw/template contract period/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
