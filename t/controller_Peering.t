use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Peering;

ok( request('/peering')->is_success || request('/peering')->is_redirect, 'Request should succeed' );
done_testing();
