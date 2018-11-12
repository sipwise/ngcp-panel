package NGCP::Panel::Form::Subscriber::CallRecordingDelete;
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }


has_field 'force_files_deletion' => (
    type => 'Boolean',
    label => 'Ignore files deletion errors',
    element_attr => {
        rel => ['tooltip'],
        title => ['Call recording infromation will be removed from database even in case of recording files absence or other impossibility to remove recording files.']
    },

);

has_field 'save' => (
    type => 'Submit',
    value => 'Delete',
    element_class => [qw/btn btn-primary/],
    do_label => 0,
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/force_files_deletion/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
