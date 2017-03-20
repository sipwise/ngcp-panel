#!/usr/bin/perl
use strict;
use warnings;
use v5.14;

use lib '../lib';
use lib '../../sipwise-base/lib';

use NGCP::Panel::Utils::Auth;
use Time::HiRes qw/gettimeofday tv_interval/;

my $t0 = [gettimeofday()];
NGCP::Panel::Utils::Auth::generate_salted_hash("testpass");
my $t1 = [gettimeofday()];

my $diff = tv_interval($t0, $t1);
say $diff;
