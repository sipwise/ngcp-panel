use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);

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
    foreach my $link(@links) {
        my $rex = qr!^</api/[a-z]+/>; rel="collection http://purl\.org/sipwise/ngcp-api/#rel-([a-z]+s)"$!;
        my ($relname) = ($link =~ $rex);
        # now get this rel
        $req = HTTP::Request->new('OPTIONS', "$uri/api/$relname/");
        $res = $ua->request($req);
        is($res->code, 200, "check options request to $relname");

        my $opts = JSON::from_json($res->decoded_content);
        ok(exists $opts->{methods}, "OPTIONS should return methods");
        is(ref $opts->{methods}, "ARRAY", "OPTIONS methods should be array");
        if ("GET" ~~ $opts->{methods}) {
            $req = HTTP::Request->new('GET', "$uri/api/$relname/");
            $res = $ua->request($req);
            is($res->code, 200, "check GET request to $relname collection")
                || diag($res->status_line);
        }
    }
}

done_testing;

# vim: set tabstop=4 expandtab:
