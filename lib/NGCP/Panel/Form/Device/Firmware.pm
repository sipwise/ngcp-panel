package NGCP::Panel::Form::Device::Firmware;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

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
);

has_field 'version' => (
    type => 'Text',
    required => 1,
    label => 'Version',
);

has_field 'data' => (
    type => 'Upload',
    required => 1,
    label => 'Firmware File',
    max_size => '671088640', # 500MB
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
