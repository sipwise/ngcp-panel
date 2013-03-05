use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Dashboard;

my $response = request('/dashboard');

ok( $response->is_success || $response->is_redirect , 'Request should succeed' );
done_testing();
