package NGCP::Panel::Field::AllContracts;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contract',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/contract/all_contracts/ajax',
    table_titles => ['#',  'Status', 'Contact Email', 'Product'],
    table_fields => ['id', 'status', 'contact_email', 'product_name'],
);

no Moose;
1;

# vim: set tabstop=4 expandtab:
