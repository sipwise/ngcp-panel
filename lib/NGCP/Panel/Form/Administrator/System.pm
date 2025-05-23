package NGCP::Panel::Form::Administrator::System;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'NGCP::Panel::Form::Administrator::Admin';

use Storable qw();

for (qw(lawful_intercept is_system)) {
    has_field $_ => (type => 'Boolean');
}
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(
        reseller login auth_mode password email role_id is_master is_active read_only enable_2fa show_passwords call_data billing_data can_reset_password
    )],
);

sub validate {
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    my $resource = Storable::dclone($self->values);
    if ($resource->{lawful_intercept} &&
        ($resource->{is_superuser} || $resource->{is_master} || $resource->{is_ccare} || $resource->{is_system} || $resource->{call_data} || $resource->{billing_data} || $resource->{show_passwords})) {
        my $err = "Administrator can be flagged as 'lafwul_intercept' only in conjunction with 'is_active', 'read_only' and 'can_reset_password' flags";
        $c->log->error($err);
        $self->field('lawful_intercept')->add_error($err);
    }

    if (defined $resource->{login} && $resource->{login} eq 'system') {
        my $err = 'Restricted login definition: ' . $resource->{login};
        $c->log->error($err);
        $self->field('login')->add_error($err);
    }
}

1;
