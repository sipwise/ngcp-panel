package NGCP::Panel::Field::TimeSet;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'TimeSet',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/peering/timesetsajax',
    table_titles => ['#', 'Name', 'Reseller #'],
    table_fields => ['id', 'name', 'reseller_id'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Reseller',
    element_class => [qw/btn btn-tertiary pull-right/],
);

no Moose;
1;
