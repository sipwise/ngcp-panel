use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ssl/ngcp/api/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ssl/ngcp/api/ca-cert.pem";

my ($ua, $req, $res, $body);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);

{
    $req = HTTP::Request->new('PATCH', $uri.'/api/systemcontacts/1');

    $res = $ua->request($req);
    is($res->code, 400, "check patch missing Prefer code");
    $body = JSON::from_json($res->decoded_content);
    ok($body->{message} =~ /Use the 'Prefer' header/, "check patch missing Prefer response");

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
    ok($body->{message} =~ /is missing a message body/, "check patch missing body response");

    $req->content(JSON::to_json(
        { foo => 'bar' },
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch no array body");
    $body = JSON::from_json($res->decoded_content);
    ok($body->{message} =~ /must be an array/, "check patch missing body response");
    
    $req->content(JSON::to_json(
        [{ foo => 'bar' }],
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch no op in body");
    $body = JSON::from_json($res->decoded_content);
    ok($body->{message} =~ /must have an 'op' field/, "check patch no op in body response");

    $req->content(JSON::to_json(
        [{ op => 'bar' }],
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch invalid op in body");
    $body = JSON::from_json($res->decoded_content);
    ok($body->{message} =~ /Invalid PATCH op /, "check patch no op in body response");

    $req->content(JSON::to_json(
        [{ op => 'test' }],
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch missing fields for op");
    $body = JSON::from_json($res->decoded_content);
    ok($body->{message} =~ /Missing PATCH keys /, "check patch missing fields for op response");

    $req->content(JSON::to_json(
        [{ op => 'test', path => '/foo', value => 'bar', invalid => 'sna' }],
    ));
    $res = $ua->request($req);
    is($res->code, 400, "check patch extra fields for op");
    $body = JSON::from_json($res->decoded_content);
    ok($body->{message} =~ /Invalid PATCH key /, "check patch extra fields for op response");
}

done_testing;

# vim: set tabstop=4 expandtab:
