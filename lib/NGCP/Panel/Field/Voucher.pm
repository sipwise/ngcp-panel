package NGCP::Panel::Field::Voucher;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Voucher',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/voucher/ajax',
    table_titles => ['#', 'Code', 'Amount','Reseller','Package','Used At'],
    table_fields => ['id', 'code', 'amount','reseller.name','profile_package_name','used_at'],
);

1;

# vim: set tabstop=4 expandtab:
