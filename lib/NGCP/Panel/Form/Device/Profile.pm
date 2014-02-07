package NGCP::Panel::Form::Device::Profile;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

with 'NGCP::Panel::Render::RepeatableJs';

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'config' => (
    type => '+NGCP::Panel::Field::DeviceConfig',
    validate_when_empty => 1,
    label => 'Device Configuration',
    element_attr => {
        rel => ['tooltip'],
        title => ['The device config to use for this profile.']
    },
);

has_field 'name' => (
    type => 'Text',
    required => 1,
    label => 'Profile Name',
    element_attr => {
        rel => ['tooltip'],
        title => ['The profile name as seen by the end customer when he provisions a new device.']
    },
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
    render_list => [qw/config name/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
