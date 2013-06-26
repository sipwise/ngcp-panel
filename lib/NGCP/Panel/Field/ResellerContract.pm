package NGCP::Panel::Field::ResellerContract;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contract',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'share/templates/helpers/datatables_field.tt',
    ajax_src => '/reseller/ajax_contract',
    table_titles => ['#', 'Contact #', 'External #', 'Status'],
    table_fields => ['id', 'contact_id', 'external_id', 'status'],
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Contract',
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
