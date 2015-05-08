package NGCP::Panel::Form::Contract::CustomerAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::BaseAPI';

has_field 'billing_profile_definition' => (
    type => 'Select',
    options => [ 
        { value => 'id', label => 'single: by \'billing_profile_id\' field' },
        { value => 'profiles', label => 'schedule: by \'billing_profiles\' field' },
        { value => 'package', label => 'package: by \'profile_package_id\' field' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Explicitly declare the way how you want to set billing profiles for this API call.']
    },
);

has_field 'billing_profiles.network_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing network id this profile is restricted to.']
    },
);

has_field 'profile_package_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile package\'s id, whose initial profile/networks are to be used to charge this contract. This field is required if the \'package\' profile definition mode is used.']
    },
);

has_field 'max_subscribers' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Optionally set the maximum number of subscribers for this contract. Leave empty for unlimited.']
    },
);

has_field 'type' => (
    type => 'Select',
    options => [
        { value => "sipaccount", label => "sipaccount"},
        { value => "pbxaccount", label => "pbxaccount"},
    ],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Either "sipaccount" or "pbxaccount".']
    },
);

has_field 'subscriber_email_template' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about subscriber creation.']
    },
);

has_field 'passreset_email_template' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about password reset.']
    },
);

has_field 'invoice_email_template' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The email template used to notify users about invoice.']
    },
);
has_field 'invoice_template' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The invoice template for invoice generation. If none is assigned, no invoice will be generated for this customer.']
    },
);

has_field 'vat_rate' => (
    type => 'Integer',
    range_start => 0,
    range_end => 100,
    default => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The VAT rate in percentage (e.g. 20).']
    },
);

has_field 'add_vat' => (
    type => 'Boolean',
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether to charge VAT in invoices.']
    },
    default => 0,
);

1;