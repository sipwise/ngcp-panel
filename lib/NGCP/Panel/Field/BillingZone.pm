package NGCP::Panel::Field::BillingZone;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Zone',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'share/templates/helpers/datatables_field.tt',
    ajax_src => '../zones/ajax', # /billing/<id>/zones/ajax
    table_titles => ['#', 'Zone', 'Zone Detail'],
    table_fields => ['id', 'zone', 'detail'],
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Zone',
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
