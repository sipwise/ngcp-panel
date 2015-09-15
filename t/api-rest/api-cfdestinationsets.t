use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my ($netloc) = ($uri =~ m!^https?://(.*)/?.*$!);

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
my $user = $ENV{API_USER} // 'administrator';
my $pass = $ENV{API_PASS} // 'administrator';
$ua->credentials($netloc, "api_admin_http", $user, $pass);

diag('Note that the next tests require at least one subscriber to be present ' .
     'and accessible to the current API user.');

# fetch a cfdestinationset for testing that
{
    $req = HTTP::Request->new('GET', $uri.'/api/cfdestinationsets/?page=1&rows=10');
    $res = $ua->request($req);
    is($res->code, 200, "fetch cfdestinationsets collection");

    $req = HTTP::Request->new('GET', $uri.'/api/cftimesets/?page=1&rows=10');
    $res = $ua->request($req);
    is($res->code, 200, "fetch cftimesets collection");
}

# fetch a cfdestinationset being a reseller
SKIP:
{
    my $user_reseller = $ENV{API_USER_RESELLER} // 'api_test';
    my $pass_reseller = $ENV{API_PASS_RESELLER} // 'api_test';
    $ua->credentials($netloc, "api_admin_http", $user_reseller, $pass_reseller);
    $req = HTTP::Request->new('GET', $uri.'/api/cfdestinationsets/?page=1&rows=10');
    $res = $ua->request($req);
    if ($res->code == 401) { # Authorization required
        skip("Couldn't login as reseller", 1);
    }
    is($res->code, 200, "fetch cfdestinationsets collection as reseller");
    my $cf_collection1 = JSON::from_json($res->decoded_content);

    $req = HTTP::Request->new('GET', $uri.'/api/cftimesets/?page=1&rows=10');
    $res = $ua->request($req);
    is($res->code, 200, "fetch cftimesets collection as reseller");
    my $cft_collection1 = JSON::from_json($res->decoded_content);

    $req = HTTP::Request->new('GET', $uri.'/api/subscribers/?page=1&rows=1');
    $res = $ua->request($req);
    is($res->code, 200, "fetch a subscriber of our reseller for testing");
    my $sub1 = JSON::from_json($res->decoded_content);
    if ($sub1->{total_count} < 1) {
        skip("Precondition not met: need a subscriber",1);
    }
    my ($sub1_id) = $sub1->{_embedded}->{'ngcp:subscribers'}->{_links}{self}{href} =~ m!subscribers/([0-9]*)$!;
    cmp_ok ($sub1_id, '>', 0, "should be positive integer");

    $req = HTTP::Request->new('GET', $uri.'/api/cfdestinationsets/?page=1&rows=10&subscriber_id='.$sub1_id);
    $res = $ua->request($req);
    is($res->code, 200, "fetch cfdestinationsets collection as reseller with subscriber filter");

    my $cf_collection2 = JSON::from_json($res->decoded_content);
    cmp_ok($cf_collection1->{total_count}, '>=', $cf_collection2->{total_count},
        "filtered collection (cfdestinationsets) should be smaller or equal");

    # --------

    $req = HTTP::Request->new('GET', $uri.'/api/cftimesets/?page=1&rows=10&subscriber_id='.$sub1_id);
    $res = $ua->request($req);
    is($res->code, 200, "fetch cftimesets collection as reseller with subscriber filter");

    my $cft_collection2 = JSON::from_json($res->decoded_content);
    cmp_ok($cft_collection1->{total_count}, '>=', $cft_collection2->{total_count},
        "filtered collection (cftimesets) should be smaller or equal");
}

{
    $ua->credentials($netloc, "api_admin_http", $user, $pass);

    $req = HTTP::Request->new('GET', "$uri/api/callforwards/99987");
    $res = $ua->request($req);
    is($res->code, 404, "check get nonexistent callforwards item");

    $req = HTTP::Request->new('GET', "$uri/api/cfdestinationsets/99987");
    $res = $ua->request($req);
    is($res->code, 404, "check get nonexistent cfdestinationsets item");

    $req = HTTP::Request->new('GET', "$uri/api/cftimesets/99987");
    $res = $ua->request($req);
    is($res->code, 404, "check get nonexistent cftimesets item");
}

done_testing;

# vim: set tabstop=4 expandtab:
