package NGCP::Panel::Form::PasswordResetAPI;

use HTML::FormHandler::Moose;
use Email::Valid;
extends 'HTML::FormHandler';

has_field 'username' => (
    type => 'Text',
    required => 1,
    label => 'Username',
);

has_field 'domain' => (
    type => 'Text',
    required => 0,
    label => 'Domain',
);

has_field 'type' => (
    type => 'Select',
    options => [
        { value => 'administrator', label => 'Administrator' },
        { value => 'subscriber', label => 'Subscriber' },
    ],
    required => 1,
    label => 'Type',
);

has_block 'fields' => (
    tag => 'div',
    class => [qw/modal-body/],
    render_list => [qw/username domain type/],
);

sub validate {
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    my $resource = Storable::dclone($self->values);
    $c->log->debug($resource->{type} . " password reset attempt for '$resource->{username}'");
    if ($resource->{type} eq 'subscriber') {
        my $err;
        if (!$resource->{domain}) {
            $err = "'domain' field is required when requesting a password reset for a subscriber";
        }
        if ($err) {
            $c->log->error($err);
            $self->field('username')->add_error($err);
        }
    }
}

1;
# vim: set tabstop=4 expandtab:
