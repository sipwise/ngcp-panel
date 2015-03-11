package NGCP::Panel::Field::Device;
use HTML::FormHandler::Moose;
use parent 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Device Model',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/device/model/ajax',
    table_titles => ['#', 'Vendor', 'Model'],
    table_fields => ['id', 'vendor', 'model'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Device Model',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
