package NGCP::Panel::Form::CallList::Subscriber;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );

has_field 'direction' => (
    type => 'Select',
    required => 1,
    options => [
        { label => "in", value => "in" },
        { label => "out", value => "out" },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Call direction, either "in" or "out"']
    },
);

has_field 'other_cli' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The CLI of the other party.']
    },
);

has_field 'status' => (
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

has_field 'type' => (
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

has_field 'customer_cost' => (
    type => 'Float',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The cost for the customer.']
    },
);

has_field 'customer_free_time' => (
    type => 'PosInteger',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The number of free seconds of the customer used for this call.']
    },
);

1;

# vim: set tabstop=4 expandtab:
