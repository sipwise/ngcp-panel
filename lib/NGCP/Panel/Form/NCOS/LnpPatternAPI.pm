package NGCP::Panel::Form::NCOS::LnpPatternAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::NCOS::Pattern';

has_field 'ncos_lnp_list_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The ncos list this pattern belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/pattern description ncos_lnp_list_id/],
);

1;

# vim: set tabstop=4 expandtab:
