package NGCP::Panel::Field::PeeringGroupSelect;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Peering Group',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/peering/ajax',
    table_titles => ['#', 'Name', 'Priority', 'Description'],
    table_fields => ['id', 'name', 'priority', 'description'],
);

no Moose;
1;
