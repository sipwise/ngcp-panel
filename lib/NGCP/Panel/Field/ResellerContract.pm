package NGCP::Panel::Field::ResellerContract;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contract',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/reseller/ajax_contract',
    table_titles => ['#', 'Contact Email', 'External #', 'Status'],
    table_fields => ['id', 'contact_email', 'external_id', 'status'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Contract',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
