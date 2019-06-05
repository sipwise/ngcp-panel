package Catalyst::Plugin::EscapeSensitiveValue;
use warnings;
use strict;
use MRO::Compat;

sub qs {
    my $c = shift;
    my $str = shift;
    return "<<" . $str . ">>" if $str;
}

1;