use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::NCOS;

ok( request('/ncos')->is_success || request('/ncos')->is_redirect, 'Request should succeed' );
done_testing();
