package NGCP::Panel::Form::Contract::CustomerAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::BaseAPI';

has_field 'billing_profiles.network_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing network id this profile is restricted to.']
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
    #required => 1,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Either "sipaccount" or "pbxaccount".']
    },
);

1;