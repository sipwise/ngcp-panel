package NGCP::Panel::Form::Call::Reseller;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );

has_field 'source_user_id' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['UUID of calling subscriber, or 0 if from external.']
    },
);

has_field 'source_provider_id' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Reseller contract id of calling subscriber, or contract id of peer if from external.']
    },
);

has_field 'source_external_subscriber_id' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['External ID of calling subscriber, if local.']
    },
);

has_field 'source_external_contract_id' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['External ID of the calling subscriber\'s customer, if local.']
    },
);

has_field 'source_customer_id' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Customer id of calling subscriber, if local.']
    },
);

has_field 'source_user' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Username of calling party.']
    },
);

has_field 'source_domain' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Domain of calling party.']
    },
);

has_field 'source_cli' => (
    type => 'Text',
    label => 'Source CLI',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Normalized CLI (usually E164) of calling party.']
    },
);

has_field 'source_clir' => (
    type => 'Boolean',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether calling party number was suppressed (CLIR).']
    },
);

has_field 'source_ip' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['IP address of calling party.']
    },
);

has_field 'source_gpp0' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 0.']
    },
);

has_field 'source_gpp1' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 1.']
    },
);

has_field 'source_gpp2' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 2.']
    },
);

has_field 'source_gpp3' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 3.']
    },
);

has_field 'source_gpp4' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 4.']
    },
);

has_field 'source_gpp5' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 5.']
    },
);

has_field 'source_gpp6' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 6.']
    },
);

has_field 'source_gpp7' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 7.']
    },
);

has_field 'source_gpp8' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 8.']
    },
);

has_field 'source_gpp9' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 9.']
    },
);

has_field 'destination_user_id' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['UUID of called subscriber, or 0 if to external.']
    },
);

has_field 'destination_provider_id' => (
    type => 'Text',
    label => 'Reseller id of called subscriber, or contract id of peer if to external',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Reseller contract id of called subscriber, or contract id of peer if to external.']
    },
);

has_field 'destination_external_subscriber_id' => (
    type => 'Text',
    label => 'external_id of called subscriber',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['External id of called subscriber, if local.']
    },
);

has_field 'destination_external_contract_id' => (
    type => 'Text',
    label => 'external_id of called subscriber',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['External id of called subscriber\'s customer, if local.']
    },
);

has_field 'destination_customer_id' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Customer id of called subscriber, if local.']
    },
);

has_field 'destination_user' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Username or number of called party.']
    },
);

has_field 'destination_domain' => (
    type => 'Text',
    label => 'Destination Domain',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Domain of called party.']
    },
);

has_field 'destination_user_dialed' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Destination username or number as received by the system from calling party before any internal rewriting.']
    },
);

has_field 'destination_user_in' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Destination username or number as received by the system from calling party after internal rewriting.']
    },
);

has_field 'destination_domain_in' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Destination domain as received by the system from calling party after internal rewriting.']
    },
);

has_field 'destination_gpp0' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 0.']
    },
);

has_field 'destination_gpp1' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 1.']
    },
);

has_field 'destination_gpp2' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 2.']
    },
);

has_field 'destination_gpp3' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 3.']
    },
);

has_field 'destination_gpp4' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 4.']
    },
);

has_field 'destination_gpp5' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 5.']
    },
);

has_field 'destination_gpp6' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 6.']
    },
);

has_field 'destination_gpp7' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 7.']
    },
);

has_field 'destination_gpp8' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 8.']
    },
);

has_field 'destination_gpp9' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['General Purpose Parameter 9.']
    },
);

has_field 'peer_auth_user' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The authentication username used for outbound authentication.']
    },
);

has_field 'peer_auth_realm' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The authentication realm (domain) used for outbound authentication.']
    },
);

has_field 'call_type' => (
    type => 'Select',
    required => 1,
    options => [
        { label => 'call', value => 'call' },
        { label => 'cfu', value => 'cfu' },
        { label => 'cfb', value => 'cfb' },
        { label => 'cft', value => 'cft' },
        { label => 'cfna', value => 'cfna' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The type of call, one of call, cfu, cfb, cft, cfna.']
    },
);

has_field 'call_status' => (
    type => 'Select',
    required => 1,
    options => [
        { label => 'ok', value => 'ok' },
        { label => 'busy', value => 'busy' },
        { label => 'noanswer', value => 'noanswer' },
        { label => 'cancel', value => 'cancel' },
        { label => 'offline', value => 'offline' },
        { label => 'timeout', value => 'timeout' },
        { label => 'other', value => 'other' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the call, one of ok, busy, noanswer, cancel, offline, timeout, other.']
    },
);

has_field 'call_code' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The final SIP response code of the call.']
    },
);

has_field 'init_time' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The timestamp of the call initiation.']
    },
);

has_field 'start_time' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The timestamp of the call connection.']
    },
);

has_field 'duration' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The duration of the call.']
    },
);

has_field 'call_id' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The value of the SIP Call-ID header for this call.']
    },
);

has_field 'source_reseller_cost' => (
    type => 'Float',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost for the reseller of the calling party towards the system operator.']
    },
);

has_field 'source_customer_cost' => (
    type => 'Float',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost for the calling party customer towards the reseller.']
    },
);

has_field 'source_reseller_free_time' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of free seconds of the reseller used for this call.']
    },
);

has_field 'source_customer_free_time' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of free seconds of the customer used for this call.']
    },
);

has_field 'source_customer_billing_fee_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing fee id used to calculate the source customer cost.']
    },
);

has_field 'source_customer_billing_zone_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The source billing zone id (from billing.billing_zones_history) attached to the customer billing cost.']
    },
);

has_field 'destination_reseller_cost' => (
    type => 'Float',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost for the reseller of the called party towards the system operator.']
    },
);

has_field 'destination_customer_cost' => (
    type => 'Float',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost for the called party customer towards the reseller.']
    },
);

has_field 'destination_reseller_free_time' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of free seconds of the reseller used for this call.']
    },
);

has_field 'destination_customer_free_time' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of free seconds of the customer used for this call.']
    },
);

has_field 'destination_customer_billing_fee_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing fee id used to calculate the destination customer cost.']
    },
);

has_field 'destination_customer_billing_zone_id' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The destination billing zone id (from billing.billing_zones_history) attached to the customer billing cost.']
    },
);



1;

# vim: set tabstop=4 expandtab:
