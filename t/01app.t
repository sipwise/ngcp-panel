#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use Catalyst::Test 'NGCP::Panel';

my $response = request('/');
ok( $response->is_success || $response->is_redirect , 'Request should succeed' );

done_testing();
