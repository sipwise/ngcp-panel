package NGCP::Panel::Form::NCOS::LnpAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::NCOS::Lnp';

has_field 'ncos_level_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The ncos level this lnp entry belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/description ncos_level_id lnp_provider/],
);

1;

# vim: set tabstop=4 expandtab:
