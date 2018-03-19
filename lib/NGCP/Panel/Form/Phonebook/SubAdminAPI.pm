package NGCP::Panel::Form::Phonebook::SubAdminAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Phonebook::API';


has_field 'shared' => (
    type => 'Boolean',
    required => 0,
    label => 'Is visible to other subscribers of the contract',
    element_attr => {
        rel => ['tooltip'],
        title => ['Is visible to other subscribers of the contract.'],
    },
);

1;