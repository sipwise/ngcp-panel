package NGCP::Panel::Form::BillingNetwork::NetworkAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'reseller_id' => (
    type => 'PosInteger',
    #required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The reseller id this billing network belongs to.']
    },
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The unique name of the billing network.']
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

has_field 'status' => (
    type => 'Hidden',
    options => [
        { value => 'active', label => 'active' },
        { value => 'terminated', label => 'terminated' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['The status of this network. Only active billing networks can be assigned to customers/profile packages.']
    },
);

has_field 'blocks' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        title => ['An array of billing network blocks, each containing the keys (base) "ip" address and an optional "mask" to specify the network portion (subnet prefix length). The specified blocks must not overlap and can uniformly contain either IPv6 addresses or IPv4 addresses.']
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
