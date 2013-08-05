package NGCP::Panel::Field::Reseller;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Reseller',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/reseller/ajax',
    table_titles => ['#', 'Name', 'Contract #', 'Status'],
    table_fields => ['id', 'name', 'contract_id', 'status'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Reseller',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;
