package NGCP::Panel::Form::Administrator::APICert;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'login' => (type => 'Text', required => 0, minlength => 5);

1;

# vim: set tabstop=4 expandtab:
