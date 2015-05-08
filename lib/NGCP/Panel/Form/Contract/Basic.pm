package NGCP::Panel::Form::Contract::Basic;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Base';

has_field 'billing_profiles.network' => (
    type => '+NGCP::Panel::Field::BillingNetwork',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing network id this profile is restricted to.']
    },
);

1;