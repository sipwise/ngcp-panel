use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Dashboard;

ok( request('/dashboard')->is_success, 'Request should succeed' );
done_testing();
