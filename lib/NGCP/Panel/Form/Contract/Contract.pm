package NGCP::Panel::Form::Contract::Contract;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Base';

has_field 'contact' => (
    type => '+NGCP::Panel::Field::Contact',
    label => 'Contact',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact id this contract belongs to.']
    },
);

#has_field 'billing_profile_definition' => (
#    type => 'Select',
#    #required => 1,
#    options => [ 
#        { value => 'id', label => 'single: by \'billing_profile_id\' field' },
#        { value => 'profiles', label => 'schedule: by \'billing_profiles\' field' },
#        #{ value => 'package', label => 'package: by \'profile_package_id\' field' },
#    ],
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['Explicitly declare the way how you want to set billing profiles for this API call.'],
#        javascript => ' onchange="switchBillingProfileDefinition(this);" ',
#    },
#    #default => 'id',
#);

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
    render_list => [qw/contact billing_profile_definition billing_profile billing_profiles profile_add status external_id subscriber_email_template passreset_email_template invoice_email_template invoice_template vat_rate add_vat/],
);

1;
# vim: set tabstop=4 expandtab: