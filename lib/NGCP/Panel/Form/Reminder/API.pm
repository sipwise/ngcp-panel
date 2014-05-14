package NGCP::Panel::Form::Reminder::API;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Reminder';
use Moose::Util::TypeConstraints;

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber this reminder belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/time recur subscriber_id/],
);

1;
# vim: set tabstop=4 expandtab:
