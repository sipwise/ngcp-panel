package NGCP::Panel::Field::TimezoneSelect;
use Moose;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'timezone' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Timezone',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/contact/timezone_ajax',
    table_titles => ['Name'],
    table_fields => ['timezone'],
);

no Moose;
1;
