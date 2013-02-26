package NGCP::Panel::Form::Login;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

with 'HTML::FormHandler::Widget::Form::Simple';

sub build_form_tags {{ error_class => 'label label-secondary'}}

has_field 'username' => (
    type => 'Text',
    required => 1,
    element_attr => { placeholder => 'Username' },
    element_class => [qw/login username-field/],
    wrapper_class => [qw/login-fields field control-group/],
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
    wrapper_class => [qw/login-fields field control-group/],
    error_class => [qw/error/],
    messages => { 
        required => 'Please provide a password' 
    },
);

has_field 'submit' => (
    type => 'Submit',
    value => 'Sign In',
    label => '',
    element_class => [qw/button btn btn-primary btn-large/],
    wrapper_class => [qw/login-actions/],
);

1;
# vim: set tabstop=4 expandtab:
