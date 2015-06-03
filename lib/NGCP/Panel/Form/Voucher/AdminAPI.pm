package NGCP::Panel::Form::Voucher::AdminAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Voucher::ResellerAPI';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this voucher belongs to.']
    },
);

1;
# vim: set tabstop=4 expandtab:
