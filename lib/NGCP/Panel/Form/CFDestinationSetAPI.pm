package NGCP::Panel::Form::CFDestinationSetAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber id this destination set belongs to.']
    },
);

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    wrapper_class => [qw/hfh-rep-field/],
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The name of the destination set.']
    },
);

has_field 'destinations' => (
    type => 'Repeatable',
    element_attr => {
        rel => ['tooltip'],
        #http://www.ietf.org/rfc/rfc3880.txt
        #http://kamailio.org/docs/modules/4.1.x/modules/tm.html
        title => ['An array of destinations, each containing the keys "destination", "timeout", "priority". ' .
                  '"destination" is a address to forward a call. ' .
                  '"timeout" is a time in seconds before call forward to the next destination or give up. ' .
                  '"priority" is a order of this destiation among others destinations for this forward type. ' .
                  '"simple_destination" is not a control field and is used only for representation purposes as a simple destination format, e.g. "4312345" if it is a number, or "user@domain" if it is a URI'
        ]
    },
);

has_field 'destinations.id' => (
    type => 'Hidden',
);

has_field 'destinations.destination' => (
    type => 'Text',
    label => 'Destination',
);

has_field 'destinations.simple_destination' => (
    type => 'Text',
    label => 'A simple destination format, e.g. "4312345" if it is a number, or "user@domain" if it is a URI.',
);

has_field 'destinations.timeout' => (
    type => '+NGCP::Panel::Field::PosInteger',
    label => 'for (seconds)',
    default => 300,
);

has_field 'destinations.priority' => (
    type => '+NGCP::Panel::Field::PosInteger',
    label => 'Priority',
    default => 1,
);

1;

# vim: set tabstop=4 expandtab:
