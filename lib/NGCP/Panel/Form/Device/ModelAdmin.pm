package NGCP::Panel::Form::Device::ModelAdmin;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Device::Model';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    not_nullable => 1,
);

has_field 'model' => (
    type => 'Text',
    required => 1,
    label => 'Model',
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
    render_list => [qw/reseller vendor model front_image mac_image/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;
# vim: set tabstop=4 expandtab:
