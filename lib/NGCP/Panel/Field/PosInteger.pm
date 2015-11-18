package NGCP::Panel::Field::PosInteger;
use Moose;
use Sipwise::Base;
use base 'HTML::FormHandler::Field::Integer';

sub validate {
    my ( $self ) = @_;
    my $value = $self->value;
    $self->add_error('Value must be a positive integer')
        if(!$self->has_errors && $value < 0);
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
