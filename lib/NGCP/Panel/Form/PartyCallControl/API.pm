package NGCP::Panel::Form::PartyCallControl::API;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'callid' => (
    type => 'Text',
    label => 'Call id',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Call id']
    },
);

has_field 'type' => (
    type => 'Text',
    label => 'Type',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['External call control request type']
    },
);

has_field 'caller' => (
    type => 'Text',
    label => 'Caller number',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Caller number']
    },
);

has_field 'callee' => (
    type => 'Text',
    label => 'Callee number',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Callee number']
    },
);

has_field 'status' => (
    type => 'Text',
    label => 'Call status',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Call status']
    },
);

has_field 'token' => (
    type => 'Text',
    label => 'Token',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['Session related token']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/callid type caller callee status token/],
);

1;

# vim: set tabstop=4 expandtab:
