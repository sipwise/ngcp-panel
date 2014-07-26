package NGCP::Panel::Field::InvoiceTemplate;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Template',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    ajax_src => '/invoicetemplate/ajax',
    template => 'helpers/datatables_field.tt',
    table_titles => ['#', 'Reseller', 'Name'],
    table_fields => ['id', 'reseller_name', 'name'],
);

1;
