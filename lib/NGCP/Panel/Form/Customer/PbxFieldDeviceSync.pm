package NGCP::Panel::Form::Customer::PbxFieldDeviceSync;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
sub build_render_list {[qw/fields actions/]}
sub build_form_element_class {[qw(form-horizontal)]}

has_field 'ip' => (
    type => 'Text',
    required => 1,
    label => 'IP Address',
);

has_field 'sync' => (
    type => 'Button',
    value => 'Push Provisioning URL',
    element_class => [qw/btn btn-primary/],
    label => '',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/ip/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/sync/],
);

sub build_form_element_attr { { id => 'devsyncform' } }

1;
# vim: set tabstop=4 expandtab:
