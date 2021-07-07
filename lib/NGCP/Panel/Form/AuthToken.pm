package NGCP::Panel::Form::AuthToken;

use HTML::FormHandler::Moose;
use NGCP::Panel::Utils::Form;
extends 'HTML::FormHandler';

has_field 'type' => (
    type => 'Select',
    options => [
        { label => 'Onetime', value => 'onetime' },
        { label => 'Expires', value => 'expires' },
    ],
    label => 'Type',
    required => 1,
);

has_field 'expires' => (
    type => '+NGCP::Panel::Field::PosInteger',
    required => 1,
    label => 'Expires',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/type expires/],
);

1;
