use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ssl/ngcp/api/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;

my $invalid_ssl_client_cert = $ENV{API_SSL_INVALID_CLIENT_CERT} || 
    "/etc/ssl/ngcp/api/NGCP-API-client-certificate.invalid.pem";
my $invalid_ssl_client_key = $ENV{API_SSL_INVALID_CLIENT_KEY} ||
    $invalid_ssl_client_cert;

my $unauth_ssl_client_cert = $ENV{API_SSL_UNAUTH_CLIENT_CERT} || 
    "/etc/ssl/ngcp/api/NGCP-API-client-certificate.unauth.pem";
my $unauth_ssl_client_key = $ENV{API_SSL_UNAUTH_CLIENT_KEY} ||
    $unauth_ssl_client_cert;

my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ssl/ngcp/api/ca-cert.pem";

my ($ua, $res);
$ua = LWP::UserAgent->new;

# invalid cert
$ua->ssl_opts(
    SSL_cert_file => $invalid_ssl_client_cert,
    SSL_key_file  => $invalid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);
$res = $ua->get($uri.'/api/');
is($res->code, 400, "check invalid client certificate")
    || note ($res->message);

# unauth cert
$ua->ssl_opts(
    SSL_cert_file => $unauth_ssl_client_cert,
    SSL_key_file  => $unauth_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);
$res = $ua->get($uri.'/api/');
is($res->code, 403, "check unauthorized client certificate")
    || note ($res->message);

# successful auth
$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);
$res = $ua->get($uri.'/api/');
is($res->code, 200, "check valid client certificate")
    || note ($res->message);

#my @links = $res->header('Link');
#ok(grep /^<\/api\/contacts\/>; rel="collection /, @links);
#ok(grep /^<\/api\/contracts\/>; rel="collection /, @links);

done_testing;

# vim: set tabstop=4 expandtab:
