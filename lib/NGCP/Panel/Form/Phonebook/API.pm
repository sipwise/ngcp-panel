package NGCP::Panel::Form::Phonebook::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'PosInteger',
    required => 0,
    label => 'ID if the phonebook entry',
    element_attr => {
        rel => ['tooltip'],
        title => ['ID if the phonebook entry'],
    },
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 0,
    label => 'Phonebook owner subscriber',
    element_attr => {
        rel => ['tooltip'],
        title => ['Id of entry owner subscriber.'],
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

1;