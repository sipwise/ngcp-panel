package NGCP::Panel::Form::PasswordChangeAPI;

use HTML::FormHandler::Moose;
use Email::Valid;
use NGCP::Panel::Utils::Form;
extends 'HTML::FormHandler';

has_field 'new_password' => (
    type => 'Password',
    required => 1,
    label => 'Password',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/new_password/],
);

sub validate_new_password {
    my ($self, $field) = @_;
    my $c = $self->form->ctx;
    return unless $c;

    NGCP::Panel::Utils::Form::validate_password(c => $c, field => $field, utf8 => 0, password_change => 1);
}

1;
# vim: set tabstop=4 expandtab:
