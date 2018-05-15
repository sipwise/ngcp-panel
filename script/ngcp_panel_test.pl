#!/usr/bin/env perl

use warnings;
use strict;

use Catalyst::ScriptRunner;
Catalyst::ScriptRunner->run('NGCP::Panel', 'Test');

1;

=head1 NAME

ngcp_panel_test.pl - Catalyst Test

=head1 SYNOPSIS

ngcp_panel_test.pl [options] uri

 Options:
   --help    display this help and exits

 Examples:
   ngcp_panel_test.pl http://localhost/some_action
   ngcp_panel_test.pl /some_action

 See also:
   perldoc Catalyst::Manual
   perldoc Catalyst::Manual::Intro

=head1 DESCRIPTION

Run a Catalyst action from the command line.

=head1 AUTHOR

Catalyst Contributors, see Catalyst.pm

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
