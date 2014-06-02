package NGCP::Panel::Form::Invoice::TemplateAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Invoice::TemplateReseller';
use Moose::Util::TypeConstraints;

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    label => 'Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id to assign this invoice template to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller name type is_active/],
);

1;

# vim: set tabstop=4 expandtab:
