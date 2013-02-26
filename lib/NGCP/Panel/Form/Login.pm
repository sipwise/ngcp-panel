package NGCP::Panel::Form::Login;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;




has_field 'username' => (
    type => 'Text',
    required => 1,
    element_attr => { placeholder => 'Username' },
    element_class => [qw/login username-field/],
    wrapper_class => [qw/field control-group/],
    error_class => [qw/error/],
    messages => { 
        required => 'Please provide a username' 
    },
);

has_field 'password' => (
    type => 'Password',
    required => 1,
    element_attr => { placeholder => 'Password' },
    element_class => [qw/login password-field/],
    wrapper_class => [qw/field control-group/],
    error_class => [qw/error/],
    messages => { 
        required => 'Please provide a password' 
    },
);

1;
# vim: set tabstop=4 expandtab:
