package NGCP::Panel::Form::Invoice::TemplateReseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the invoice template.'],
    },
);

has_field 'type' => (
    type => 'Select',
    label => 'Type',
    required => 1,
    options => [
        { label => 'SVG', value => 'svg' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The invoice template type (only svg for now).'],
    },
);

has_field 'call_direction' => (
    type => 'Select',
    label => 'Call direction',
    required => 1,
    options => [
        { label => 'incoming calls only', value => 'in' },
        { label => 'outgoing calls only', value => 'out' },
        { label => 'incoming and outgoing calls', value => 'in_out' },
    ],
    default => 'out',
    element_attr => {
        rel => ['tooltip'],
        title => ['The call directions to include in the invoice.'],
    },
);

has_field 'category' => (
    type => 'Select',
    label => 'Category',
    required => 1,
    options => [
        { label => 'customer', value => 'customer' },
        { label => 'peer', value => 'peer' },
        { label => 'reseller', value => 'reseller' },
        { label => 'did', value => 'did' },
    ],
    default => 'customer',
    element_attr => {
        rel => ['tooltip'],
        title => ['The category of the invoice.'],
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
    render_list => [qw/name type call_direction category/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
