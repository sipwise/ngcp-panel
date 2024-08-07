package NGCP::Panel::Form::PasswordChange;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

use HTML::FormHandler::Widget::Block::Bootstrap;

has '+widget_wrapper' => ( default => 'Bootstrap' );

sub build_form_tags {{ error_class => 'label label-secondary'}}

has_field 'username' => (
    type => 'Text',
    required => 1,
    element_attr => { placeholder => 'Username' },
    element_class => [qw/login username-field/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'password' => (
    type => 'Password',
    required => 1,
    element_attr => { placeholder => 'Password' },
    element_class => [qw/login password-field/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'new_password' => (
    type => 'Password',
    required => 1,
    element_attr => { placeholder => 'New Password' },
    element_class => [qw/login password-field/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'new_password2' => (
    type => 'Password',
    required => 1,
    element_attr => { placeholder => 'New Password Again' },
    element_class => [qw/login password-field/],
    wrapper_class => [qw/login-fields field control-group/],
);

has_field 'submit' => (
    type => 'Submit',
    value => 'Submit',
    label => '',
    element_class => [qw/button btn btn-primary btn-large/],
);

1;
# vim: set tabstop=4 expandtab:
