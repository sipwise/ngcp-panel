package NGCP::Panel::Form::Contract::PeeringResellerAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::PeeringReseller';

has_field 'billing_profile' => (
    type => '+NGCP::Panel::Field::BillingProfile',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile id used to charge this contract.']
    },
);

has_field '+billing_profiles' => ( #or override this one to drop the required flag
    required => 0,
);

has_field 'type' => (
    type => 'Select',
    options => [
        { value => 'sippeering', label => 'Peering'},
        { value => 'reseller', label => 'Reseller'},
    ],
    #required => 1,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Either "sippeering" or "reseller".']
    },
);

has_field 'billing_profiles.type' => (
    type => 'Select',
    options => [
        { value => 'sippeering', label => 'Peering'},
        { value => 'reseller', label => 'Reseller'},
    ],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Either "sippeering" or "reseller".']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profile billing_profiles status external_id type/],
);

1;
# vim: set tabstop=4 expandtab:
