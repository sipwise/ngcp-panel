package NGCP::Panel::Field::Domain;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Domain',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'share/templates/helpers/datatables_field.tt',
    ajax_src => '/domain/ajax',
    table_titles => ['Domain'],
    table_fields => ['domain'],
);

has_field 'create' => (
    type => 'Button',
    label => 'or',
    value => 'Create Domain',
    element_class => [qw/btn btn-tertiary/],
);

1;

# vim: set tabstop=4 expandtab:
