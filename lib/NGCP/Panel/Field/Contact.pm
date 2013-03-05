package NGCP::Panel::Field::Contact;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'foo' => (
    type => '+NGCP::Panel::Field::ContactSelect',
    label => 'Contact',
    required => 1,
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Contact',
    element_attr => { onclick => 'window.location=\'/contact/create\'' },
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
