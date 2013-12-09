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

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);

# OPTIONS tests
{
    # test some uri params
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/?foo=bar&bla');
    $res = $ua->request($req);
    ok($res->code == 200, "check options request with uri params");

    $req = HTTP::Request->new('OPTIONS', $uri.'/api/');
    $res = $ua->request($req);
    ok($res->code == 200, "check options request");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
    foreach my $opt(qw( PUT POST DELETE )) {
        ok(!grep(/^$opt$/, @hopts), "check for non-existence of '$opt' in Allow header");
        ok(!grep(/^$opt$/, @{ $opts->{methods} }), "check for non-existence of '$opt' in body");
    }

    my @links = $res->header('Link');
    my $rels = { contracts => 1, contacts => 1, };
    foreach my $link(@links) {
        ok($link =~ /^<\/api\/[a-z]+\/>; rel=\"collection http:\/\/purl\.org\/sipwise\/ngcp-api\/#rel-([a-z]+s)\"$/, "check for valid link syntax");
        ok(exists $rels->{$1}, "check for '$1' collection in Link");
        delete $rels->{$1};
    }
    ok(keys %{ $rels } == 0, "check if all collections are present in Link");
}

done_testing;

# vim: set tabstop=4 expandtab:
