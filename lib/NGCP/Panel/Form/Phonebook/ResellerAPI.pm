package NGCP::Panel::Form::Phonebook::ResellerAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Phonebook::API';

has_field 'contract_id' => (
    type => 'PosInteger',
    required => 1,
    label => 'Phonebook owner contract',
    element_attr => {
        rel => ['tooltip'],
        title => ['Id of entry owner contract.'],
    },
);

1;