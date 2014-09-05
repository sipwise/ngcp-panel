package NGCP::Panel::Field::Contract;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contract',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/contract/peering/ajax',
    table_titles => ['#',  'Status', 'Contact Email', 'Billing Profile'],
    table_fields => ['id', 'status', 'contact_email', 'billing_mappings_actual_billing_mappings_billing_profile_name'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Contract',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
