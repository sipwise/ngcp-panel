package NGCP::Panel::Field::Contract;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contract',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'share/templates/helpers/datatables_field.tt',
    ajax_src => '/contract/peering/ajax',
    table_titles => ['#', 'Contact #', 'Billing Profile #', 'Status'],
    table_fields => ['id', 'contact.id', 'billing_profile.id', 'status'],
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Contract',
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
