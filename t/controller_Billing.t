use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Billing;

ok( request('/billing')->is_success, 'Request should succeed' );
done_testing();
