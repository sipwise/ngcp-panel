package NGCP::Panel::Form::CallQueue::API;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'id' => (
    type => 'Hidden',
    noupdate => 1,
);

has_field 'queue_length' => (
    type => 'Integer',
    required => 0,
    default => '0',
    element_attr => {
        rel => ['tooltip'],
        title => ['The length of the call queue.']
    },
);

has_field 'queue' => (
    type => 'Repeatable',
    do_wrapper => 1,
    do_label => 0,
    required => 0,
    element_attr => {
        rel => ['tooltip'],
        title => ['Number of Objects, each containing the key ' .
                  '"call_id" (queued call id).'],
    },
);

1;
