package NGCP::Panel::Form::Contract::PeeringReseller;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Base';

has_field 'contact' => (
    type => '+NGCP::Panel::Field::ContactNoReseller',
    label => 'Contact',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact id this contract belongs to.']
    },
);

has_field 'billing_profiles.profile' => (
    type => '+NGCP::Panel::Field::BillingProfile',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile used to charge this contract.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profile_definition billing_profile billing_profiles profile_add status external_id/],
);

1;
# vim: set tabstop=4 expandtab:
