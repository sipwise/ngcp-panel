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
}

# fetch a cfdestinationset being a reseller
{
    $ua->credentials($netloc, "api_admin_http", 'api_test', 'api_test');
    $req = HTTP::Request->new('GET', $uri.'/api/cfdestinationsets/?page=1&rows=10&subscriber_id=83');
    $res = $ua->request($req);
    is($res->code, 200, "fetch cfdestinationsets collection");

    use DDP; p $res;

    $ua->credentials($netloc, "api_admin_http", 'api_test', 'api_test');
    $req = HTTP::Request->new('GET', $uri.'/api/cfdestinationsets/?page=1&rows=10');
    $res = $ua->request($req);
    is($res->code, 200, "fetch cfdestinationsets collection");

    use DDP; p $res;
}



done_testing; exit;


# MT#14803 test nonexistent cf
{
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
