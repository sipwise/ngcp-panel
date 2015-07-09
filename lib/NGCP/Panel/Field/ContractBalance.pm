package NGCP::Panel::Field::ContractBalance;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Balance Interval',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/somewhere/ajax',
    table_titles => ['#', 'bla', 'blah'],
    table_fields => ['id', 'x', 'y'],
);

1;

# vim: set tabstop=4 expandtab:
