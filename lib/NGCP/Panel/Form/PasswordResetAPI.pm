package NGCP::Panel::Form::PasswordResetAPI;

use HTML::FormHandler::Moose;
extends 'HTML::FormHandler';

has_field 'email' => (
    type => 'Email',
    required => 1,
    label => 'Email/Username',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/username/],
);

1;
# vim: set tabstop=4 expandtab:
