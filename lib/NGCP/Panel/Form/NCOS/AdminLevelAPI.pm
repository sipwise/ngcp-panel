package NGCP::Panel::Form::NCOS::AdminLevelAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::NCOS::ResellerLevelAPI';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller this level belongs to.']
    },
);

1;

# vim: set tabstop=4 expandtab:
