use warnings;
use strict;

use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use Test::More;
use File::Temp qw/tempfile/;

#use IO::Socket::SSL;
#$IO::Socket::SSL::DEBUG = 1;
use Data::Dumper;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

#docker: CATALYST_SERVER=https://10.15.20.104:1443 perl t/api-rest/api-cert-auth.t

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT};
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;

my $invalid_ssl_client_cert = $ENV{API_SSL_INVALID_CLIENT_CERT};
my $invalid_ssl_client_key = $ENV{API_SSL_INVALID_CLIENT_KEY} ||
    $invalid_ssl_client_cert;

my $unauth_ssl_client_cert = $ENV{API_SSL_UNAUTH_CLIENT_CERT};
my $unauth_ssl_client_key = $ENV{API_SSL_UNAUTH_CLIENT_KEY} ||
    $unauth_ssl_client_cert;

my $ssl_ca_cert = $ENV{API_SSL_CA_CERT};

unless ($valid_ssl_client_cert && $ssl_ca_cert) {
    ($valid_ssl_client_cert, $ssl_ca_cert) = _download_certs($uri);
    $valid_ssl_client_key = $valid_ssl_client_cert;
}

my ($ua, $res);
$ua = LWP::UserAgent->new;

SKIP: {
    unless ( $invalid_ssl_client_cert && (-e $invalid_ssl_client_cert) ) {
        skip ("Skip Invalid client certificate, we have none", 1);
    }
    # invalid cert
    $ua->ssl_opts(
        SSL_cert_file => $invalid_ssl_client_cert,
        SSL_key_file  => $invalid_ssl_client_key,
        SSL_ca_file   => $ssl_ca_cert,
    );
    $res = $ua->get($uri.'/api/');
    is($res->code, 400, "check invalid client certificate")
        || note ($res->message);
}

SKIP: {
    unless ( $unauth_ssl_client_cert && (-e $unauth_ssl_client_cert) ) {
        skip ("Skip unauthorized client certificate, we have none", 1);
    }
    # unauth cert
    $ua->ssl_opts(
        SSL_cert_file => $unauth_ssl_client_cert,
        SSL_key_file  => $unauth_ssl_client_key,
        SSL_ca_file   => $ssl_ca_cert,
    );
    $res = $ua->get($uri.'/api/');
    is($res->code, 403, "check unauthorized client certificate")
        || note ($res->message);
}

# successful auth
print Dumper {
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
};
$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file => $valid_ssl_client_key,
    SSL_verify_mode => 0,
    verify_hostname => 0,
);
$res = $ua->get($uri.'/api/');
print Dumper $res;
is($res->code, 200, "check valid client certificate")
    || note ($res->message);

#my @links = $res->header('Link');
#ok(grep /^<\/api\/contacts\/>; rel="collection /, @links);
#ok(grep /^<\/api\/contracts\/>; rel="collection /, @links);

done_testing;

sub _download_certs {
    my ($uri) = @_;
    my ($ua, $req, $res);
    $ua = LWP::UserAgent->new(cookie_jar => {}, ssl_opts => {verify_hostname => 0, SSL_verify_mode => 0});
    $res = $ua->post($uri.'/login/admin', {username => 'administrator', password => 'administrator'}, 'Referer' => $uri.'/login/admin');
    $res = $ua->get($uri.'/dashboard/');
    $res = $ua->get($uri.'/administrator/1/api_key');
    if ($res->decoded_content =~ m/gen\.generate/) { # key need to be generated first
        $res = $ua->post($uri.'/administrator/1/api_key', {'gen.generate' => 'foo'}, 'Referer' => $uri.'/dashboard');
    }
    my (undef, $tmp_apiclient_filename) = tempfile;
    my (undef, $tmp_apica_filename) = tempfile;
    $res = $ua->post($uri.'/administrator/1/api_key', {'pem.download' => 'foo'}, 'Referer' => $uri.'/dashboard', ':content_file' => $tmp_apiclient_filename);
    $res = $ua->post($uri.'/administrator/1/api_key', {'ca.download' => 'foo'}, 'Referer' => $uri.'/dashboard', ':content_file' => $tmp_apica_filename);
    diag ("Client cert: $tmp_apiclient_filename - CA cert: $tmp_apica_filename\n");
    return ($tmp_apiclient_filename, $tmp_apica_filename);
}

# vim: set tabstop=4 expandtab:
