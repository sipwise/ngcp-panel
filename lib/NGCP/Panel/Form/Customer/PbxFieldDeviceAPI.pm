package NGCP::Panel::Form::Customer::PbxFieldDeviceAPI;

use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has_field 'customer' => (
    type => '+NGCP::Panel::Field::CustomerContract',
    label => 'Customer',
    validate_when_empty => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The customer contract this device is belonging to.']
    },
);

has_field 'profile' => (
    type => 'Compound',
);
has_field 'profile.id' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    label => 'Device Profile',
);

has_field 'identifier' => (
    type => 'Text',
    required => 1,
    label => 'MAC Address / Identifier',
);

has_field 'station_name' => (
    type => 'Text',
    required => 1,
    label => 'Station Name',
);

has_field 'lines' => (
    type => 'Repeatable',
    label => 'Lines/Keys',
    setup_for_js => 1,
    do_wrapper => 1,
    do_label => 1,
    required => 1,
    tags => {
        controls_div => 1,
    },
    wrapper_class => [qw/hfh-rep-block/],
    element_attr => {
        rel => ['tooltip'],
        title => ["The lines for this pbx device. Required keys are 'linerange' (name of range to use), 'key_num' (key number in line range, starting from 0), 'type' (one of 'private', 'shared', 'blf'), 'subscriber_id' (the subscriber mapped to this key)."],
    },
);

has_field 'lines.linerange' => (
    type => 'Text',
    required => 1,
    label => 'Linerange',
    element_attr => {
        rel => ['tooltip'],
        title => ['The linerange name to use.'],
    },
);

has_field 'lines.subscriber_id' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    label => 'Subscriber',
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber to use on this line/key'],
    },
);

has_field 'lines.key_num' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    label => 'Line/Key Number (starting from 0)',
    element_attr => {
        rel => ['tooltip'],
        title => ['The line/key to use (starting from 0)'],
    },
);

has_field 'lines.type' => (
    type => 'Select',
    required => 1,
    label => 'Line/Key Type',
    options => [
        { label => "private", value => "private" },
        { label => "shared", value => "shared" },
        { label => "blf", value => "blf" },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The type of feature to use on this line/key'],
    },
    element_class => [qw/ngcp-linetype-select/],
);

1;
# vim: set tabstop=4 expandtab:
