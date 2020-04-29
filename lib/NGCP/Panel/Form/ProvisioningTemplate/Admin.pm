package NGCP::Panel::Form::ProvisioningTemplate::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::ProvisioningTemplate::Reseller';

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this template belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller name description lang yaml/],
);

1;