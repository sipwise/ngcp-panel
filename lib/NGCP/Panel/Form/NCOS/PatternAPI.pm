package NGCP::Panel::Form::NCOS::PatternAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::NCOS::Pattern';
use Moose::Util::TypeConstraints;

has_field 'ncos_level_id' => (
    type => 'PosInteger',
    required => 1,
    element_attr => {
        rel => ['tooltip'],
        title => ['The ncos level this pattern belongs to.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/pattern description ncos_level_id/],
);

1;

# vim: set tabstop=4 expandtab:
