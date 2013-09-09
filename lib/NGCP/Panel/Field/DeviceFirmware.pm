package NGCP::Panel::Field::DeviceFirmware;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Compound';

has_field 'id' => (
    type => '+NGCP::Panel::Field::DataTable',
    label => 'Device Firmware',
    do_label => 0,
    do_wrapper => 0,
    required => 1,
    template => 'helpers/datatables_field.tt',
    ajax_src => '/device/firmware/ajax',
    table_titles => ['#', 'Device Vendor', 'Device Model', 'Filename'],
    table_fields => ['id', 'device_vendor', 'device_model', 'filename'],
);

has_field 'create' => (
    type => 'Button',
    do_label => 0,
    value => 'Create Device Firmware',
    element_class => [qw/btn btn-tertiary pull-right/],
);

1;

# vim: set tabstop=4 expandtab:
