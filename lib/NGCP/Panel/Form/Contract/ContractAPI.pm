package NGCP::Panel::Form::Contract::ContractAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::BaseAPI';

has_field 'billing_profile_definition' => (
    type => 'Select',
    #required => 1,
    options => [ 
        { value => 'id', label => 'single: by \'billing_profile_id\' field' },
        { value => 'profiles', label => 'schedule: by \'billing_profiles\' field' },
        #{ value => 'package', label => 'package: by \'profile_package_id\' field' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Explicitly declare the way how you want to set billing profiles for this API call.']
    },
    #default => 'id',
);

#has_field 'billing_profiles.network_id' => (
#    type => 'PosInteger',
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['The billing network id this profile is restricted to.']
#    },
#);

#has_field 'max_subscribers' => (
#    type => 'PosInteger',
#    required => 0,
#    element_attr => {
#        rel => ['tooltip'],
#        title => ['Optionally set the maximum number of subscribers for this contract. Leave empty for unlimited.']
#    },
#);

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

1;