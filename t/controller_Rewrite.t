use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Rewrite;

ok( request('/rewrite')->is_success || request('/rewrite')->is_redirect, 'Request should succeed' );
done_testing();
