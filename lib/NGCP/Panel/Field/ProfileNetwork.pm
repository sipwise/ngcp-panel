package NGCP::Panel::Field::ProfileNetwork;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'profile_id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Profile',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/billing/ajax',
    table_titles => ['#', 'Reseller', 'Profile'],
    table_fields => ['id', 'reseller_name', 'name'],
);

has_field 'network_id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Network',
    do_label => 0,
    do_wrapper => 0,
    required => 0,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/network/ajax',
    table_titles => ['#', 'Reseller', 'Network'],
    table_fields => ['id', 'reseller_name', 'name'],
);

1;

# vim: set tabstop=4 expandtab:
