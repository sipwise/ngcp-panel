package NGCP::Panel::Field::ContactNoReseller;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contact',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/contact/ajax_noreseller',
    table_titles => ['#', 'First Name', 'Last Name', 'Email'],
    table_fields => ['id', 'firstname', 'lastname', 'email'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Contact',
    element_class => [qw/btn btn-tertiary pull-right/],
);

no Moose;
1;

# vim: set tabstop=4 expandtab:
