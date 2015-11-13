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
my $login_response = $c->login($comx_user, $comx_pass, $comx_netloc);
ok($c->login_status, "Login done");
is($c->login_status->{code}, 200, "Login successful");

    #p $c->get_sessions;
#p $c->create_session_and_account('npa4V0YkavioQ1GW7Yob', 'sip4', 'sip:alice@192.168.51.150', 'alicepass', 'YAqON76yLVtgMgBYeg6v');
#p $c->get_networks;
my $network = $c->create_network('gjungwirth_test', 'sip-connector', {xms => JSON::false}, 'YAqON76yLVtgMgBYeg6v');
ok($network, "Create Network");
is($network->{code}, 201, "Create Network successful");
ok($network->{data}{id}, "Got a network id");

#p $c->create_session_and_account('npa4V0YkavioQ1GW7Yob', 'sip', 'user1@bar.com', '123456', 'YAqON76yLVtgMgBYeg6v');

my $tmp_resp = $c->delete_network($network->{data}{id});
is($tmp_resp->{code}, 200, "Delete Network");

ok(1,"stub, done");
done_testing;