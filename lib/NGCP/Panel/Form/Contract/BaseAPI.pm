package NGCP::Panel::Form::Contract::BaseAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has_field 'contact_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contact id this contract belongs to.']
    },
);

has_field 'billing_profile_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile id used to charge this contract, which will become active immediately. This field is required if the profile definition mode is not defined or the \'id\' mode is used.']
    },
);

has_field 'billing_profiles' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile / billing network interval schedule used to charge this contract can be specified. It is represented by an array of objects, each containing the keys "start", "stop", "profile_id" and "network_id" (/api/customers/ only). When POSTing, it has to contain a single interval with empty "start" and "stop" fields. Only intervals beginning in the future can be updated afterwards. This field is required if the \'profiles\' profile definition mode is used.']
    },
);

has_field 'billing_profiles.id' => (
    type => 'Hidden',
);

has_field 'billing_profiles.profile_id' => (
    type => 'PosInteger',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing profile id used to charge this contract.']
    },
);

has_field 'billing_profiles.start' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile gets active.']
    },
);

has_field 'billing_profiles.stop' => (
    type => '+NGCP::Panel::Field::DateTime',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The datetime (YYYY-MM-DD HH:mm:ss) when the billing profile is revoked.']
    },
);

has_field 'status' => (
    type => 'Select',
    required => 1,
    options => [ 
        { label => 'active', value => 'active' },
        { label => 'pending', value => 'pending' },
        { label => 'locked', value => 'locked' },
        { label => 'terminated', value => 'terminated' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the contract.']
    },
);

has_field 'external_id' => (
    type => 'Text',
    required => 0,
    element_attr => { 
        rel => ['tooltip'], 
        title => ['An external id, e.g. provided by a 3rd party provisioning'] 
    },
);

1;
# vim: set tabstop=4 expandtab:
