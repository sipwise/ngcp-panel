package NGCP::Panel::Form::Contract::PeeringReseller;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Basic';

has_field 'contact.id' => (
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

1;
# vim: set tabstop=4 expandtab:
