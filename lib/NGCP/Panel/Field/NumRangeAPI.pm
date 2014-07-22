package NGCP::Panel::Field::NumRangeAPI;
use Sipwise::Base;
extends 'HTML::FormHandler::Field::Text';

has 'min_start' => (isa => 'Int', default => 0, is => 'rw');
has 'max_end' => (isa => 'Int', default => 999_999, is => 'rw');

sub validate {
    my ( $self ) = @_;
    my ($start, $end) = $self->value =~ m/(\d+)-(\d+)/;
    unless ($start && $end && $start >= 0 && $end >= 0) {
        $self->add_error('Invalid format');
        return;
    }
    if ($end < $start) {
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

1;

# vim: set tabstop=4 expandtab:
