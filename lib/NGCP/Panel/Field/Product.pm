package NGCP::Panel::Field::Product;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Product',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/product/ajax',
    table_titles => ['#', 'Name'],
    table_fields => ['id', 'name'],
);

1;

# vim: set tabstop=4 expandtab:
