package NGCP::Panel::Form::Voicemail::Greeting;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+enctype' => ( default => 'multipart/form-data');
has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );

has_field 'dir' => (
    type => 'Select',
    required => 1,
    options => [
        { value => 'unavail', label => 'Unavailable' },
        { value => 'busy', label => 'Busy' },
    ],
    element_attr => {
        rel => ['tooltip'],
        title => ['Greeting type.'],
    },
);

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Subscriber owning the greeting.'],
    },
);

1;

# vim: set tabstop=4 expandtab:
