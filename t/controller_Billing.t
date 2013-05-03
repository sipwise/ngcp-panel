use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Billing;

ok( request('/billing')->is_success || request('/billing')->is_redirect, 'Request should succeed' );
done_testing();
