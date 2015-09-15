use warnings;
use strict;

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

# OPTIONS tests
{
    diag("server is $uri");
    # test some uri params
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/?foo=bar&bla');
    $res = $ua->request($req);
    is($res->code, 200, "check options request with uri params");

    $req = HTTP::Request->new('OPTIONS', $uri.'/api/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');

    my @links = $res->header('Link');
    my $rex = qr!^</api/[a-z]+/>; rel="collection http://purl\.org/sipwise/ngcp-api/#rel-([a-z]+s|topupcash)"$!;
    foreach my $link(@links) {
        (my ($relname)) = ($link =~ $rex);
        # now get this rel
        $req = HTTP::Request->new('OPTIONS', "$uri/api/$relname/");
        $res = $ua->request($req);
        is($res->code, 200, "check options request to $relname");

        my $opts = JSON::from_json($res->decoded_content);
        ok(exists $opts->{methods}, "OPTIONS should return methods");
        is(ref $opts->{methods}, "ARRAY", "OPTIONS methods should be array");
        if (grep {$_ eq "GET"} @{ $opts->{methods} }) {
            # skip calllists collection, as it needs a subscriber_id parameter also in the collection
            next if $relname eq "calllists";
            $req = HTTP::Request->new('GET', "$uri/api/$relname/");
            $res = $ua->request($req);
            is($res->code, 200, "check GET request to $relname collection")
                || diag($res->status_line);
        }
    }
}

done_testing;

# vim: set tabstop=4 expandtab:
