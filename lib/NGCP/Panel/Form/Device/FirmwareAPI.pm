package NGCP::Panel::Form::Device::FirmwareAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
has '+enctype' => ( default => 'multipart/form-data');
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'device_id' => (
    type => 'PosInteger',
    required => 1,
    label => 'Device Model',
    element_attr => {
        rel => ['tooltip'],
        title => ['The pbx device model id this firmware belongs to.']
    },
);

has_field 'version' => (
    type => 'Text',
    required => 1,
    label => 'Version',
    element_attr => {
        rel => ['tooltip'],
        title => ['The version number of this firmware.']
    },
);

has_field 'filename' => (
    type => 'Text',
    required => 1,
    label => 'Filename',
    element_attr => {
        rel => ['tooltip'],
        title => ['The filename of this firmware.']
    },
);

has_field 'tag' => (
    type => 'Text',
    required => 0,
    label => 'Tag',
    element_attr => {
        rel => ['tooltip'],
        title => ['A custom tag for this firmware.']
    },
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/device_id version filename tag/],
);

1;
# vim: set tabstop=4 expandtab:
