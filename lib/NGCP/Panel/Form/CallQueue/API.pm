package NGCP::Panel::Form::CallQueue::API;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
    noupdate => 1,
);

has_field 'queue' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Number of Objects, each containing the keys ' .
                  '"destinationset", "timeset" and "sourceset". The values must be the name of ' .
                  'a corresponding set which belongs to the same subscriber.'],
    },
);

1;
