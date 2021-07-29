package NGCP::Panel::Form::PasswordRecoveryAPI;

use HTML::FormHandler::Moose;
use Email::Valid;
use NGCP::Panel::Utils::Form;
extends 'HTML::FormHandler';

has_field 'new_password' => (
    type => 'Password',
    required => 1,
    label => 'Password',
);

has_field 'token' => (
    type => 'Text',
    required => 1,
    label => 'Token',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/new_password token/],
);

sub validate_new_password {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_password(c => $c, field => $field, utf8 => 0);
}

1;
# vim: set tabstop=4 expandtab:
