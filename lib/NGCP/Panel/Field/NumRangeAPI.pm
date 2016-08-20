package NGCP::Panel::Field::NumRangeAPI;
use Moose;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Text';

has 'min_start' => (isa => 'Int', default => 0, is => 'rw');
has 'max_end' => (isa => 'Int', default => 999_999, is => 'rw');
has 'cyclic' => (isa => 'Bool', default => 0, is => 'rw');

sub validate {
    my ( $self ) = @_;
    my ($start, $end) = split(/\-/, $self->value);
    $end //= $start;
    unless ((defined $start) && (defined $end) && $start >= 0 && $end >= 0) {
        $self->add_error('Invalid format');
        return;
    }
    if ( (!$self->cyclic) && ($end < $start) ) {
        $self->add_error('Second value smaller than first');
        return;
    }
    if ($start < $self->min_start) {
        $self->add_error('First value too small');
        return;
    }
    if ($end > $self->max_end) {
        $self->add_error('Second value too big');
        return;
    }
    return;
}

no Moose;
1;

# vim: set tabstop=4 expandtab:
