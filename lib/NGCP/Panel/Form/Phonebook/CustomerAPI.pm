package NGCP::Panel::Form::Phonebook::CustomerAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    required => 0,
    label => 'Phonebook entry id',
    element_attr => {
        rel => ['tooltip'],
        title => ['Phonebook entry id'],
    },
);

has_field 'customer_id' => (
    type => 'PosInteger',
    required => 0,
    label => 'Phonebook entry contract id',
    element_attr => {
        rel => ['tooltip'],
        title => ['Phonebook entry customer id'],
    },
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    label => 'Phonebook entry name',
    element_attr => {
        rel => ['tooltip'],
        title => ['The full entry name "e.g. John Smith".'],
    },
);

has_field 'number' => (
    type => 'Text',
    required => 1,
    label => 'Phonebook number',
    element_attr => {
        rel => ['tooltip'],
        title => ['The phonebook number, can be either as a numeric or a SIP number.' ],
    },
);

has_field 'own' => (
    type => 'Boolean',
    required => 0,
    default_value => 0,
    label => 'Number allegiance',
    element_attr => {                                                                                                                             rel => ['tooltip'],                                                                                                                       title => ['Defines if the Phonebook entry belongs to the customer'],
    },
);

1;
