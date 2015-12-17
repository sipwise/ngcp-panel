use warnings;
use strict;
use Test::More;

use NGCP::Panel::Utils::ComxAPIClient;

my $comx_host = $ENV{COMX_HOST} // 'https://rtcengine.sipwise.com/rtcengine/api';
my $comx_user = $ENV{COMX_USER} // 'gjungwirth@sipwise';
my $comx_pass = $ENV{COMX_PASS};
my $comx_netloc = $comx_host =~ s!^https://([^/:]*)(:[0-9]*)?/.*$!$1.($2||":443")!re;  # 'rtcengine.sipwise.com:443'

my $COLLECTION_TARGET = '/users';

my $comx = NGCP::Panel::Utils::ComxAPIClient->new(
    host => $comx_host,
);
$comx->login($comx_user, $comx_pass, $comx_netloc);
ok($comx->login_status, "Login done");
is($comx->login_status->{code}, 200, "Login successful");

my $users1 = $comx->_resolve_collection($COLLECTION_TARGET);
isa_ok($users1, 'HASH', 'Collection Method 1');
ok($users1->{response}, 'Collection Method 1 - has response');
ok($users1->{response}->is_success, 'Collection Method 1 - response successful');
isa_ok($users1->{data}, 'ARRAY', 'Collection Method 1 - has data');

my $users2 = $comx->_resolve_collection_fast($COLLECTION_TARGET);
isa_ok($users2, 'HASH', 'Collection Method 2');
ok($users2->{response}, 'Collection Method 2 - has response');
ok($users2->{response}->is_success, 'Collection Method 2 - response successful');
isa_ok($users2->{data}, 'ARRAY', 'Collection Method 2 - has data');

is($users1->{total_count}, $users2->{total_count}, 'total_count is the same');
map {delete $_->{href}} @{ $users2->{data} };
is_deeply($users1->{data}, $users2->{data}, 'they are the same');

ok(1,"stub, done");
done_testing;