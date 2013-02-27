use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Reseller;

ok( request('/reseller')->is_success, 'Request should succeed' );
done_testing();
