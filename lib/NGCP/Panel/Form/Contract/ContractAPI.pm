package NGCP::Panel::Form::Contract::ContractAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::BaseAPI';

has_field 'contact_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact id this contract belongs to.'],
        expand => {
            class => 'NGCP::Panel::Role::API::SystemContacts',
            allowed_roles => [qw(admin)],
        },
    },
);

has_field 'billing_profile_definition' => (
    type => 'Select',
    #required => 1,
    options => [
        { value => 'id', label => 'single: by \'billing_profile_id\' field' },
        { value => 'profiles', label => 'schedule: by \'billing_profiles\' field' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Explicitly declare the way how you want to set billing profiles for this API call.']
    },
);

has_field 'type' => (
    type => 'Select',
    options => [
        { value => "sippeering", label => "sippeering"},
        { value => "reseller", label => "reseller"},
    ],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Either "sippeering" or "reseller".']
    },
);

has_field 'max_subscribers' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Optionally set the maximum number of subscribers for this contract (reseller only). Leave empty for unlimited.']
    },
);


1;
