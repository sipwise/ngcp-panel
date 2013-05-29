package NGCP::Panel::Field::BillingProfile;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Billing Profile',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'share/templates/helpers/datatables_field.tt',
    ajax_src => '/billing/ajax',
    table_titles => ['#', 'Profile'],
    table_fields => ['id', 'name'],
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Contract',
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
