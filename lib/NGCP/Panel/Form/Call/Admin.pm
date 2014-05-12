package NGCP::Panel::Form::Call::Admin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Call::Reseller';
use Moose::Util::TypeConstraints;

has_field 'source_carrier_cost' => (
    type => 'Float',
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost for the operator towards the peering carrier.']
    },
);

has_field 'source_carrier_free_time' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of free seconds of the carrier contract for this call.']
    },
);

has_field 'source_carrier_billing_fee_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing fee id used to calculate the source carrier cost.']
    },
);

has_field 'source_reseller_billing_fee_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing fee id used to calculate the source reseller cost.']
    },
);

has_field 'source_carrier_billing_zone_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The source billing zone id (from billing.billing_zones_history) attached to the carrier billing cost.']
    },
);

has_field 'source_reseller_billing_zone_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The source billing zone id (from billing.billing_zones_history) attached to the reseller billing cost.']
    },
);

has_field 'destination_carrier_cost' => (
    type => 'Float',
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost for the carrier towards the operator (e.g. for 800-numbers).']
    },
);

has_field 'destination_carrier_free_time' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of free seconds of the carrier contract for this call.']
    },
);

has_field 'destination_carrier_billing_fee_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing fee id used to calculate the destination carrier cost.']
    },
);

has_field 'destination_reseller_billing_fee_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The billing fee id used to calculate the destination reseller cost.']
    },
);

has_field 'destination_carrier_billing_zone_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The destination billing zone id (from billing.billing_zones_history) attached to the carrier billing cost.']
    },
);

has_field 'destination_reseller_billing_zone_id' => (
    type => 'PosInteger',
    element_attr => {
        rel => ['tooltip'],
        title => ['The destination billing zone id (from billing.billing_zones_history) attached to the reseller billing cost.']
    },
);

has_field 'rated_at' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['The timestamp when the rating occured.']
    },
    required => 0,
);

has_field 'rating_status' => (
    type => 'Select',
    options => [
        { label => 'unrated', 'value' => 'unrated' },
        { label => 'ok', 'value' => 'ok' },
        { label => 'failed', 'value' => 'failed' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the rating process.']
    },
);

has_field 'exported_at' => (
    type => 'Text',
    element_attr => {
        rel => ['tooltip'],
        title => ['The timestamp when the exporting occured.']
    },
    required => 0,
);

has_field 'export_status' => (
    type => 'Select',
    options => [
        { label => 'unexported', 'value' => 'unexported' },
        { label => 'ok', 'value' => 'ok' },
        { label => 'failed', 'value' => 'failed' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of the exporting process.']
    },
);

1;

# vim: set tabstop=4 expandtab:
