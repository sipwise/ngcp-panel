package NGCP::Panel::Form::CallControl::CallAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'subscriber_id' => (
    type => 'PosInteger',
    label => 'Subscriber #',
    required => 1,
    maxlength => 255,
    element_attr => {
        rel => ['tooltip'],
        title => ['The ID of the calling subscriber']
    },
);

has_field 'destination' => (
    type => 'Text',
    label => 'Destination URI, user or number',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The destination URI, user or number as dialed by the end user']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/subscriber_id destination/],
);

1;

# vim: set tabstop=4 expandtab:
