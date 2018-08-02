package NGCP::Panel::Field::IntegerList;
use NGCP::Panel::Utils::Generic qw(:all);
use Sipwise::Base;
use HTML::FormHandler::Moose;
extends 'HTML::FormHandler::Field::Text';

has 'min_value' => (isa => 'Int', default => 0, is => 'rw');
has 'max_value' => (isa => 'Int', default => 999_999, is => 'rw');
has 'plusminus' => (isa => 'Bool', default => 0, is => 'rw');

sub validate {
    my ( $self ) = @_;
    my @integers = split(/,/, $self->value);
    for my $single_int (@integers) {
        $single_int = abs( $single_int ) if $self->plusminus;
        if ( !is_int($single_int) ) {
            $self->add_error('Value in IntegerList is not numeric.');
            return;
        }
        if ($single_int < $self->min_value) {
            my $min_value = $self->min_value;
            $self->add_error("Value in IntegerList ($single_int) is too small (min: $min_value).");
            return;
        }
        if ($single_int > $self->max_value) {
            my $max_value = $self->max_value;
            $self->add_error("Value in IntegerList ($single_int) is too big (max: $max_value).");
            return;
        }
    }
    return;
}

no Moose;
1;

# vim: set tabstop=4 expandtab:

# describes a list of comma-separated integer numbers (mainly to be used for iCal)
# the integers have to be within the defined range (min_value, max_value)