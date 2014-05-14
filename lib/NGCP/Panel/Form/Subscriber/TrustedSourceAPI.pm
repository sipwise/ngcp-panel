package NGCP::Panel::Form::Subscriber::TrustedSourceAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Subscriber::TrustedSource';
use Moose::Util::TypeConstraints;

has_field 'subscriber_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The subscriber this trusted source belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/src_ip protocol from_pattern subscriber_id/],
);

1;
# vim: set tabstop=4 expandtab:
