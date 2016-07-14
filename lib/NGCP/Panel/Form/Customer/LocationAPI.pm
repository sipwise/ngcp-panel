package NGCP::Panel::Form::Customer::LocationAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'contract_id' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The contract id this location belongs to.']
    },
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The unique name of the location.']
    },
);

has_field 'description' => (
    type => 'Text',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['Arbitrary text.'],
    },
);

has_field 'blocks' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of location blocks, each containing the keys (base) "ip" address and an optional "mask" to specify the network portion (subnet prefix length). The specified blocks must not overlap and can uniformly contain either IPv6 addresses or IPv4 addresses.']
    },
);

has_field 'blocks.ip' => (
    type => '+NGCP::Panel::Field::IPAddress',
    required => 1,
    label => '(Base) IP Address',
);

has_field 'blocks.mask' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 0,
    label => 'Subnet Prefix Length',
);

1;

# vim: set tabstop=4 expandtab:
