package NGCP::Panel::Form::CFDestinationSetAPI;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
use Moose::Util::TypeConstraints;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
);

has_field 'subscriber' => ( # Workaround for validate_form
    type => 'Compound',
);

has_field 'subscriber.id' => (
    type => 'PosInteger',
);

has_field 'name' => (
    type => 'Text',
    label => 'Name',
    wrapper_class => [qw/hfh-rep-field/],
    required => 1,
);

has_field 'destinations' => (
    type => 'Repeatable',
);

has_field 'destinations.id' => (
    type => 'Hidden',
);

has_field 'destinations.destination' => (
    type => 'Text',
    label => 'Destination',
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
