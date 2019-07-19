package Catalyst::Plugin::EscapeJs;
use warnings;
use strict;
use MRO::Compat;

sub escape_js {
    my $c = shift;
    my $str = shift;
    my $quote_char = shift;
    $quote_char //= "'";
    $str =~ s/\\/\\\\/g;
    $str =~ s/$quote_char/\\$quote_char/g;
    return $str;
}

1;