package NGCP::Panel::Form::Device::Firmware;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
has '+enctype' => ( default => 'multipart/form-data');
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'device' => (
    type => '+NGCP::Panel::Field::Device',
    validate_when_empty => 1,
    label => 'Device Model',
    element_attr => {
        rel => ['tooltip'],
        title => ['The device model id this firmware belongs to.']
    },
);

has_field 'version' => (
    type => 'Text',
    required => 1,
    label => 'Version',
    element_attr => {
        rel => ['tooltip'],
        title => ['The version of this firmware (e.g. 5.3a)']
    },
);

has_field 'data' => (
    type => 'Upload',
    required => 1,
    label => 'Firmware File',
    max_size => '67108864', # 64MB
    element_attr => {
        rel => ['tooltip'],
        title => ['The actual firmware data.']
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
    render_list => [qw/device version data/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
