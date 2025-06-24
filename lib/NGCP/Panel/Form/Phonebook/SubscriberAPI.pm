package NGCP::Panel::Form::Phonebook::SubscriberAPI;

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
    label => 'Phonebook entry customer id',
    element_attr => {
        rel => ['tooltip'],
        title => ['Phonebook entry customer id'],
    },
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 0,
    label => 'Phonebook entry subscriber id',
    element_attr => {
        rel => ['tooltip'],
        title => ['Phonebook entry subscriber id'],
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

has_field 'shared' => (
    type => 'Boolean',
    required => 0,
    default_value => 0,
    label => 'Share phonebook entry',
    element_attr => {
        rel => ['tooltip'],
        title => ['Define if the Phonebook entry is visible to other subscribers within the same contract'],
    },
);

1;
