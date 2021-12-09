package NGCP::Panel::Form::Administrator::SystemAPI;

use HTML::FormHandler::Moose;
extends 'NGCP::Panel::Form::Administrator::System';

use Storable qw();

has_field 'role' => (
    type => 'Text'
);

sub validate {
    my $self = shift;

    $self->SUPER::validate(@_);

    my $c = $self->ctx;
    return unless $c;

    my $resource = Storable::dclone($self->values);

    if (defined $resource->{role} && ! ref $resource->{role}) {
        if (!defined NGCP::Panel::Utils::UserRole::name_to_flags($resource->{role})) {
            my $err = 'Unknown role: ' . $resource->{role};
            $c->log->error($err);
            $self->field('role')->add_error($err);
        }
    }
}

1;
