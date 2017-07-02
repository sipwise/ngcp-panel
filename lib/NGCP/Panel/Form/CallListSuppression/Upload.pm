package NGCP::Panel::Form::CallListSuppression::Upload;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has '+enctype' => ( default => 'multipart/form-data');
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }

has_field 'upload_calllistsuppression' => (
    type => 'Upload',
    max_size => '2097152000', # 2GB
);

has_field 'purge_existing' => (
    type => 'Boolean',
);

has_field 'save' => (
    type => 'Submit',
    value => 'Upload',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/upload_calllistsuppression purge_existing/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
