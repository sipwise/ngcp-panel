package NGCP::Panel::Field::CustomerContract;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Customer',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/customer/ajax',
    table_titles => ['#', 'Reseller', 'Contact Email', 'External #', 'Status'],
    table_fields => ['id', 'contact_reseller_name', 'contact_email', 'external_id', 'status'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Contract',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
