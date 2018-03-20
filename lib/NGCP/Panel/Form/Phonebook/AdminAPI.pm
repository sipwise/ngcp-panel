package NGCP::Panel::Form::Phonebook::AdminAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Phonebook::ResellerAPI';

has_field 'reseller_id' => (
    type => 'PosInteger',
    required => 1,
    label => 'Phonebook owner reseller',
    element_attr => {
        rel => ['tooltip'],
        title => ['Id of entry owner reseller.'],
    },
);

1;