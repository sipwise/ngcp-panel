package NGCP::Panel::Field::PosInteger;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Integer';

sub validate {
    my ( $self ) = @_;
    my $value = $self->value;
    $self->add_error('Value must be a positive integer')
        if(!$self->has_errors && $value < 0);
}

1;

# vim: set tabstop=4 expandtab:
