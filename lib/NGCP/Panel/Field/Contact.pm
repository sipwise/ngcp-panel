package NGCP::Panel::Field::Contact;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'contact' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contact',
    required => 1,
    do_wrapper => 0,
    ajax_src => '/contact/ajax',
    table_fields => ['#', 'First Name', 'Last Name', 'Email'],
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Contact',
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
