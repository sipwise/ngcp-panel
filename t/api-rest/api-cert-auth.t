use warnings;
use strict;

use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use Test::More;
use File::Temp qw/tempfile/;
use Test::Collection;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

#docker: CATALYST_SERVER=https://10.15.20.104:1443 perl t/api-rest/api-cert-auth.t

my ($invalid_ssl_client_cert, $valid_ssl_client_cert) = _download_certs($uri);

my ($ua, $res);
$ua = LWP::UserAgent->new;

SKIP1:
{
    # invalid cert
    $ua->ssl_opts(
        SSL_cert_file => $invalid_ssl_client_cert,
        SSL_key_file  => $invalid_ssl_client_cert,
        SSL_verify_mode => 0,
        verify_hostname => 0,
    );
    $res = $ua->head($uri.'/api/');
    is($res->code, 403, "check invalid client certificate")
        || note ($res->message);
}
SKIP2:
{
    $ua->ssl_opts(
        SSL_cert_file => $valid_ssl_client_cert,
        SSL_key_file => $valid_ssl_client_cert,
        SSL_verify_mode => 0,
        verify_hostname => 0,
    );
    $res = $ua->head($uri.'/api/');
    is($res->code, 200, "check valid client certificate")
        || note ($res->message);
}

# just to generate a new cert on file system cache:
$ua = Test::Collection->new()->ua();

done_testing;

sub _download_certs {
    my ($uri) = @_;
    my ($ua, $req, $res);

    my $invalid_cert = '/tmp/invalidcert.pem';
    my $valid_cert = '/tmp/validcert.pem';

    -f $invalid_cert && unlink $invalid_cert;
    -f $valid_cert && unlink $valid_cert;

    my $coll = Test::Collection->new();
    rename $coll->ssl_cert, $invalid_cert;
    $coll->clear_cert;
    rename $coll->ssl_cert, $valid_cert;

    return ($invalid_cert, $valid_cert);
}

# vim: set tabstop=4 expandtab:
