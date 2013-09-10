package NGCP::Panel::Form::Device::Model;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+enctype' => ( default => 'multipart/form-data');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'vendor' => (
    type => 'Text',
    required => 1,
    label => 'Vendor',
);

has_field 'model' => (
    type => 'Text',
    required => 1,
    label => 'Model',
);

has_field 'front_image' => (
    type => 'Upload',
    required => 0,
    label => 'Front Image',
    max_size => '67108864', # 64MB
);

has_field 'mac_image' => (
    type => 'Upload',
    required => 0,
    label => 'MAC Address Image',
    max_size => '67108864', # 64MB
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
    render_list => [qw/vendor model front_image mac_image/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
