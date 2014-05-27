package NGCP::Panel::Form::NumberBlock::BlockAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::NumberBlock::BlockReseller';
use Moose::Util::TypeConstraints;

has_field 'reseller_list' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Resellers',
    do_label => 0,
    do_wrapper => 0,
    required => 0,
    template => 'helpers/datatables_multifield.tt',
    ajax_src => '/reseller/ajax',
    table_titles => ['#', 'Reseller'],
    table_fields => ['id', 'name'],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/reseller_list e164 allocable/],
);

1;

# vim: set tabstop=4 expandtab:
