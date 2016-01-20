#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

eval { require Test::Perl::Critic; };
 
if ( $@ ) {
    my $msg = 'Test::Perl::Critic required to criticise code';
    plan( skip_all => $msg );
}

use Perl::Critic::Command qw//;

my %options  = Perl::Critic::Command::_get_options();
my @files    = Perl::Critic::Command::_get_input(@ARGV);

Test::Perl::Critic->import( %options );

all_critic_ok(@files);
