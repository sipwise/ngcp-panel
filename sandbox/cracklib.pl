#!/usr/bin/perl
use strict;
use warnings;
use English;

use Crypt::Cracklib;

my $pass = $ARGV[0];
unless(defined $pass) {
    die "Usage: $PROGRAM_NAME <password>\n";
}

if(check($pass)) {
    print "Password ok\n";
} else {
    print "Password NOT ok\n";
}
