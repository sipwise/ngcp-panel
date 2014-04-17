package NGCP::Panel::Field::PbxGroup;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Group',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    # this is set in the form:
    #ajax_src => '/',
    table_titles => ['#', 'Name', 'Extension'],
    table_fields => ['id', 'username', 'provisioning_voip_subscriber_pbx_extension'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Group',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
