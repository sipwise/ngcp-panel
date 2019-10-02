package Catalyst::Plugin::NGCP::EscapeSensitiveValue;
use warnings;
use strict;
use MRO::Compat;

sub qs {
    my $c = shift;
    my $str = shift;
    return "\x{ab}" . $str . "\x{bb}" if $str;
    #return "<<" . $str . ">>" if $str;
}

1;
