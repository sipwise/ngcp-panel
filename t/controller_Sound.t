use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Sound;

ok( request('/sound')->is_success || request('/sound')->is_redirect, 'Request should succeed' );
done_testing();
