package NGCP::Panel::Form::Number::AdminAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Number::SubadminAPI';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller this number belongs to.']
    },
);

1;
# vim: set tabstop=4 expandtab:
