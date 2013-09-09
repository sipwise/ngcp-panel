package NGCP::Panel::Form::Device::Profile;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'firmware' => (
    type => '+NGCP::Panel::Field::DeviceFirmware',
    not_nullable => 0,
    label => 'Device Firmware',
);

has_field 'config' => (
    type => '+NGCP::Panel::Field::DeviceConfig',
    not_nullable => 1,
    label => 'Device Configuration',
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    label => 'Profile Name',
);

has_field 'save' => (
    type => 'Submit',
    value => 'Save',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/firmware config name/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
