package NGCP::Panel::Field::BillingProfile;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Billing Profile',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/billing/ajax',
    table_titles => ['#', 'Reseller', 'Profile'],
    table_fields => ['id', 'reseller_name', 'name'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Billing Profile',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
