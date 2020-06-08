package NGCP::Panel::Form::Administrator::System;
use HTML::FormHandler::Moose;
use HTML::FormHandler::Widget::Block::Bootstrap;
extends 'NGCP::Panel::Form::Administrator::Reseller';

use Storable qw();

for (qw(is_superuser lawful_intercept is_system)) {
    has_field $_ => (type => 'Boolean',);
}
has_field 'reseller' => (
    type => '+NGCP::Panel::Field::Reseller',
    label => 'Reseller',
    validate_when_empty => 1,
);
has_block 'fields' => (
    tag => 'div',
    class => [qw(modal-body)],
    render_list => [qw(
        reseller login password email is_superuser is_master is_ccare is_active read_only show_passwords call_data billing_data lawful_intercept can_reset_password is_system
    )],
);

sub validate {
    my ($self) = @_;
    my $c = $self->ctx;
    return unless $c;

    my $resource = Storable::dclone($self->values);
    if ($resource->{is_ccare} && $resource->{lawful_intercept}) {
        my $err = "Administrator cannot be ccare and lawful intercept at the same time.";
        $c->log->error($err);
        $self->field('is_ccare')->add_error($err);
        $self->field('lawful_intercept')->add_error($err);
    }
}

1;
