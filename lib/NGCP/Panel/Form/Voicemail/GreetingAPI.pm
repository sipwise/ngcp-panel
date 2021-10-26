package NGCP::Panel::Form::Voicemail::GreetingAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Voicemail::Greeting';

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
        { value => 'greet', label => 'Greeting' },
        { value => 'temp', label => 'Temporary' },
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

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/greetingfile dir subscriber_id/],
);

1;

# vim: set tabstop=4 expandtab:
