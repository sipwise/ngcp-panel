use warnings;
use strict;
use Test::More;

use NGCP::Panel::Utils::ComxAPIClient;

my $comx_host = $ENV{COMX_HOST} // 'https://rtcengine.sipwise.com/rtcengine/api';
my $comx_user = $ENV{COMX_USER} // 'gjungwirth@sipwise';
my $comx_pass = $ENV{COMX_PASS};
my $comx_netloc = $comx_host =~ s!^https://([^/:]*)(:[0-9]*)?/.*$!$1.($2||":443")!re;  # 'rtcengine.sipwise.com:443'

my $c = NGCP::Panel::Utils::ComxAPIClient->new(
    host => $comx_host,
);
$c->login($comx_user, $comx_pass, $comx_netloc);
ok($c->login_status, "Login done");
is($c->login_status->{code}, 200, "Login successful");

#goto delete_u_only;

my $user = $c->create_user('foo@ngcptest.com', 'mypassabcdefg');
ok($user, "Create user");
is($user->{code}, 201, "Create user successful");
ok($user->{data}{id}, "Got a user id");
is(length($user->{data}{id}), 20, "User id follows format");

#p $c->get_sessions;
#p $c->create_session_and_account('npa4V0YkavioQ1GW7Yob', 'sip4', 'sip:alice@192.168.51.150', 'alicepass', 'YAqON76yLVtgMgBYeg6v');
#p $c->get_networks;
my $network = $c->create_network('gjungwirth_test', 'sip-connector', {xms => JSON::false}, 'YAqON76yLVtgMgBYeg6v');
ok($network, "Create Network");
is($network->{code}, 201, "Create Network successful");
ok($network->{data}{id}, "Got a network id");
is(length($network->{data}{id}), 20, "Network id follows format");

my $app = $c->create_app('gjungwirth_test_app', 'www.example.tld', $user->{data}{id});
ok($app, "Create App");
is($app->{code}, 201, "Create App successful");
ok($app->{data}{id}, "Got an app id");
is(length($app->{data}{id}), 20, "App id follows format");

########################

$c->login('foo@ngcptest.com', 'mypassabcdefg', $comx_netloc);
ok($c->login_status, "Login (as created user) done");
is($c->login_status->{code}, 200, "Login (as created user) successful");

my $network2 = $c->create_network('gjungwirth_test_as_subuser', 'sipwise-connector', {xms => JSON::false}, $user->{data}{id});
ok($network2, "Create Network (as subuser)");
is($network2->{code}, 201, "Create Network successful (as subuser)");
ok($network2->{data}{id}, "Got a network id (as subuser)");

my $tmp_resp = $c->delete_network($network2->{data}{id});
is($tmp_resp->{code}, 200, "Delete Network (as subuser)");

$c->login($comx_user, $comx_pass, $comx_netloc);
ok($c->login_status, "Login done (as original user)");
is($c->login_status->{code}, 200, "Login successful (as original user)");

########################

#p $c->create_session_and_account('npa4V0YkavioQ1GW7Yob', 'sip', 'user1@bar.com', '123456', 'YAqON76yLVtgMgBYeg6v');

$tmp_resp = $c->delete_network($network->{data}{id});
is($tmp_resp->{code}, 200, "Delete Network");

$tmp_resp = $c->delete_app($app->{data}{id});
is($tmp_resp->{code}, 200, "Delete App");

delete_u_only:

$tmp_resp = $c->delete_user($user->{data}{id});
is($tmp_resp->{code}, 200, "Delete User");

ok(1,"stub, done");
done_testing;