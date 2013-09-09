package NGCP::Panel::Field::DeviceConfig;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Device Configuration',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/device/config/ajax',
    table_titles => ['#', 'Device Vendor', 'Device Model', 'Version'],
    table_fields => ['id', 'device_vendor', 'device_model', 'version'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Device Configuration',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
