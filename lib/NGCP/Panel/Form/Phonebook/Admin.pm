package NGCP::Panel::Form::Phonebook::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Phonebook::Reseller';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id to assign this phonebook entry to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/id reseller name number/],
);

1;
# vim: set tabstop=4 expandtab:
