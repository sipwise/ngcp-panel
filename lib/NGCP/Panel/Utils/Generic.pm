package NGCP::Panel::Utils::Generic;
use strict;
use warnings;
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(is_int is_integer is_decimal merge compare);
%EXPORT_TAGS = ( DEFAULT => [qw(&is_int &is_integer &is_decimal &merge &compare)],
                 all    =>  [qw(&is_int &is_integer &is_decimal &merge &compare)]);

use Hash::Merge;
use Data::Compare qw//;

sub is_int {
    my $val = shift;
    if($val =~ /^[+-]?[0-9]+$/) {
        return 1;
    }
    return;
}

sub is_integer {
    return is_int(@_);
}

sub is_decimal {
    my $val = shift;
    # TODO: also check if only 0 or 1 decimal point
    if($val =~ /^[+-]?\.?[0-9\.]+$/) {
        return 1;
    }
    return;
}

sub merge {
    my ($a, $b) = @_;
    return Hash::Merge::merge($a, $b);
}

# 0 if different, 1 if equal
sub compare {
    return Data::Compare::Compare(@_);
}

1;
