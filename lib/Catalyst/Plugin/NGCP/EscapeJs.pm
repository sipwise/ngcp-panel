package Catalyst::Plugin::NGCP::EscapeJs;
use warnings;
use strict;
use MRO::Compat;

use NGCP::Panel::Utils::Generic qw();

sub escape_js {
    my $c = shift;
    return NGCP::Panel::Utils::Generic::escape_js(@_);
}

1;
