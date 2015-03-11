package NGCP::Panel::Form::CallList::Subscriber;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
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

has_field 'own_cli' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The CLI of the own party. For PBX subscribers it is always the PBX extension, otherwise the source_cli or destination_user_in. CLI format is denormalized by caller-out rewrite rule of subscriber.']
    },
);

has_field 'other_cli' => (
    type => 'Text',
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['The CLI of the other party, or null if CLIR was active. For intra-PBX calls it is the PBX extension, for inter-PBX calls it is the value of the field specified by the alias_field parameter if available, otherwise the souce_cli or destination_user_in. CLI format is denormalized by caller-out rewrite rule of subscriber.']
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

has_field 'intra_customer' => (
    type => 'Boolean',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Whether it is a call between subscribers of one single customer.']
    },
);

has_field 'call_id' => (
    type => 'Text',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The internal SIP Call-ID of the call.']
    },
);

1;

# vim: set tabstop=4 expandtab:
