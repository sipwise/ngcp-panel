package NGCP::Panel::Field::Country;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Country',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/contact/country/ajax',
    table_titles => ['#', 'Country'],
    table_fields => ['id', 'name'],
);

1;
