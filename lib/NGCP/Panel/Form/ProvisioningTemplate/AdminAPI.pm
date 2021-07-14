package NGCP::Panel::Form::ProvisioningTemplate::AdminAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::ProvisioningTemplate::ResellerAPI';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this template belongs to.']
    },
);

1;