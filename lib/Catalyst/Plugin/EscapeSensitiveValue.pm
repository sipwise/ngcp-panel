package Catalyst::Plugin::EscapeSensitiveValue;
use strict;
use MRO::Compat;

sub qs {
    my $c = shift;
    my $str = shift;
    return "<<" . $str . ">>" if $str;
}

1;