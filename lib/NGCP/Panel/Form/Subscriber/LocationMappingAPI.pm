package NGCP::Panel::Form::Subscriber::LocationMappingAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Subscriber::LocationMapping';

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber this location mapping belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/subscriber_id location caller_pattern callee_pattern mode to_username external_id enabled/],
);

1;
# vim: set tabstop=4 expandtab:
