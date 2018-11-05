package NGCP::Panel::Form::Voicemail::Greeting;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+enctype' => ( default => 'multipart/form-data');
has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );
sub build_render_list {[qw/submitid fields actions/]}
sub build_form_element_class { [qw/form-horizontal/] }


has_field 'greetingfile' => (
    type => 'Upload',
    required => 1,
    label => 'Voicemail greeting file. Must be a audio file in the "wav" format with "gsm" encoding. Content-type should be "audio/x-wav" or "application/octet-stream" in a "multipart/form-data" request',
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
    render_list => [qw/greetingfile/],
);

has_block 'actions' => (
    tag => 'div',
    class => [qw/modal-footer/],
    render_list => [qw/save/],
);

1;

# vim: set tabstop=4 expandtab:
