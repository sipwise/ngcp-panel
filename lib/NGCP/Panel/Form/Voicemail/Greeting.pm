package NGCP::Panel::Form::Voicemail::Greeting;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+enctype' => ( default => 'multipart/form-data');
has '+widget_wrapper' => ( default => 'Bootstrap' );
has_field 'submitid' => ( type => 'Hidden' );


has_field 'greetingfile' => ( 
    type => 'Upload',
    max_size => '67108864', # 64MB
);


1;

# vim: set tabstop=4 expandtab:
