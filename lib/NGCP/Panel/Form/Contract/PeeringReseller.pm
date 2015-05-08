package NGCP::Panel::Form::Contract::PeeringReseller;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Contract::Base';

has_field 'contact.id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Contact',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/contact/ajax_noreseller', #another ajax url
    table_titles => ['#', 'First Name', 'Last Name', 'Email'],
    table_fields => ['id', 'firstname', 'lastname', 'email'],
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/contact billing_profiles profile_add status external_id/],
);

1;
# vim: set tabstop=4 expandtab:
