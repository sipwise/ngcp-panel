package NGCP::Panel::Field::BillingNetwork;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Network',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/billing/ajax',
    table_titles => ['#', 'Reseller', 'Network'],
    table_fields => ['id', 'reseller_name', 'name'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Billing Network',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
