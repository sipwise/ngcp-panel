use strict;
use warnings;
use Test::More;


use Catalyst::Test 'NGCP::Panel';
use NGCP::Panel::Controller::Reseller;

my $response = request('/reseller');
ok( $response->is_success || $response->is_redirect , 'Request should succeed' );
done_testing();
