use strict;
use warnings;

use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my ($ua, $req, $res);

use Test::Collection;
$ua = Test::Collection->new()->ua();

my $body;

{
    $req = HTTP::Request->new('PATCH', $uri.'/api/systemcontacts/1');

    $req->header('Prefer' => 'return=minimal');
    $res = $ua->request($req);
    is($res->code, 415, "check patch missing media type");

    $req->header('Content-Type' => 'application/xxx');
    $res = $ua->request($req);
    is($res->code, 415, "check patch invalid media type");

    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/json-patch+json');

    $res = $ua->request($req);
    is($res->code, 400, "check patch missing body");
    $body = JSON::from_json($res->decoded_content);
    like($body->{message}, qr/is missing a message body/, "check patch missing body response");

    $req->content(JSON::to_json(
        { foo => 'bar' },
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch no array body");
    $body = JSON::from_json($res->decoded_content);
    like($body->{message}, qr/must be an array/, "check patch missing body response");
    
    $req->content(JSON::to_json(
        [{ foo => 'bar' }],
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch no op in body");
    $body = JSON::from_json($res->decoded_content);
    like($body->{message}, qr/must have an 'op' field/, "check patch no op in body response");

    $req->content(JSON::to_json(
        [{ op => 'bar' }],
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch invalid op in body");
    $body = JSON::from_json($res->decoded_content);
    like($body->{message}, qr/Invalid PATCH op /, "check patch no op in body response");

    $req->content(JSON::to_json(
        [{ op => 'replace' }],
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch missing fields for op");
    $body = JSON::from_json($res->decoded_content);
    like($body->{message}, qr/Missing PATCH keys /, "check patch missing fields for op response");

    $req->content(JSON::to_json(
        [{ op => 'replace', path => '/foo', value => 'bar', invalid => 'sna' }],
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch extra fields for op");
    $body = JSON::from_json($res->decoded_content);
    like($body->{message}, qr/Invalid PATCH key /, "check patch extra fields for op response");
}

done_testing;

# vim: set tabstop=4 expandtab:
