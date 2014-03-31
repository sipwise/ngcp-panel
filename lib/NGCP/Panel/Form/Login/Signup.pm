package NGCP::Panel::Form::Login::Signup;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';
use Moose::Util::TypeConstraints;

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );

sub build_form_tags {{ error_class => 'label label-secondary'}}

has_field 'firstname' => (
    type => 'Text',
    required => 1,
    element_attr => { placeholder => 'First Name' },
    element_class => [qw/login/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'lastname' => (
    type => 'Text',
    required => 1,
    element_attr => { placeholder => 'Last Name' },
    element_class => [qw/login/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'email' => (
    type => 'Email',
    required => 1,
    element_attr => { placeholder => 'Email' },
    element_class => [qw/login/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'username' => (
    type => 'Text',
    required => 1,
    element_attr => { placeholder => 'Username' },
    element_class => [qw/login/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'password' => (
    type => 'Password',
    required => 1,
    minlength => 7,
    ne_username => 'username',
    element_attr => { placeholder => 'Password' },
    element_class => [qw/login/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'confirmpassword' => (
    type => 'PasswordConf',
    required => 1,
    password_field => 'password',
    element_attr => { placeholder => 'Confirm Password' },
    element_class => [qw/login/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'agree' => (
    type => 'Checkbox',
    required => 1,
    do_label => 0,
    option_label => 'I have read and agree with the Terms of Use.',
    element_class => [qw/login-checkbox/],
    wrapper_class => [qw/login-actions/],
);

has_field 'submit' => (
    type => 'Submit',
    value => 'Register',
    label => '',
    element_class => [qw/button btn btn-primary btn-large/],
    wrapper_class => [qw/login-actions/],
);

1;
# vim: set tabstop=4 expandtab:
