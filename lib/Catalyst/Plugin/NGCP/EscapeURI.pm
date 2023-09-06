package Catalyst::Plugin::NGCP::EscapeURI;
use warnings;
use strict;
use MRO::Compat;

use NGCP::Panel::Utils::Generic qw();

sub escape_uri {
    my $c = shift;
    return NGCP::Panel::Utils::Generic::escape_uri(@_);
}

1;
