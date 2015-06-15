use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;
use Storable qw();
use Data::Printer;

use JSON::PP;
use LWP::Debug;

BEGIN {
    unshift(@INC,'../lib');
}

my $json = JSON::PP->new();
$json->allow_blessed(1);
$json->convert_blessed(1);

my $is_local_env = $ENV{LOCAL_TEST} // 0;
my $mysql_sqlstrict = 1; #https://bugtracker.sipwise.com/view.php?id=12565

use Config::General;
my $catalyst_config;
if ($is_local_env) {
    my $panel_config;
    for my $path(qw#../ngcp_panel.conf ngcp_panel.conf#) {
        if(-f $path) {
            $panel_config = $path;
            last;
        }
    }
    $panel_config //= '../ngcp_panel.conf';
    $catalyst_config = Config::General->new($panel_config);   
} else {
    #taken 1:1 from /lib/NGCP/Panel.pm
    my $panel_config;
    for my $path(qw#/etc/ngcp-panel/ngcp_panel.conf etc/ngcp_panel.conf ngcp_panel.conf#) {
        if(-f $path) {
            $panel_config = $path;
            last;
        }
    }
    $panel_config //= 'ngcp_panel.conf';
    $catalyst_config = Config::General->new($panel_config);   
}
my %config = $catalyst_config->getall();

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

if ($is_local_env) {
    $ua->ssl_opts(
        verify_hostname => 0,
    );
    my $realm = $uri; $realm =~ s/^https?:\/\///;
    $ua->credentials($realm, "api_admin_http", 'administrator', 'administrator');
    #$ua->timeout(500); #useless, need to change the nginx timeout
} else {
    $ua->ssl_opts(
        SSL_cert_file => $valid_ssl_client_cert,
        SSL_key_file  => $valid_ssl_client_key,
        SSL_ca_file   => $ssl_ca_cert,
    );    
}

my $t = time;
my $default_reseller_id = 1;

test_voucher();
done_testing();


sub test_voucher {
    my $code = 'testcode'.$t;
    my $voucher = {
        amount => 100,
        code => $code,
        customer_id => undef,
        reseller_id => $default_reseller_id,
        valid_until => '2037-01-01 12:00:00',
    };
    $req = HTTP::Request->new('POST', $uri.'/api/vouchers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json($voucher));
    $res = $ua->request($req);
    is($res->code, 201, _get_request_test_message("POST test voucher"));
    my $voucher_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $voucher_uri);
    $res = $ua->request($req);
    is($res->code, 200, _get_request_test_message("fetch POSTed test voucher"));
    my $post_voucher = JSON::from_json($res->decoded_content);
    delete $post_voucher->{_links};
    my $voucher_id = delete $post_voucher->{id};
    is_deeply($voucher, $post_voucher, "check POSTed voucher against fetched");
    $post_voucher->{id} = $voucher_id;

    $req = HTTP::Request->new('PUT', $voucher_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json($post_voucher));
    $res = $ua->request($req);
    is($res->code, 200, _get_request_test_message("PUT test voucher"));
    $req = HTTP::Request->new('GET', $voucher_uri);
    $res = $ua->request($req);
    is($res->code, 200, _get_request_test_message("fetch PUT test voucher"));
    my $put_voucher = JSON::from_json($res->decoded_content);
    delete $put_voucher->{_links};
    $voucher_id = delete $put_voucher->{id};
    is_deeply($voucher, $put_voucher, "check PUTed voucher against POSTed voucher");

    $req = HTTP::Request->new('PATCH', $voucher_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json([{op=>"replace", path=>"/code", value=>$put_voucher->{code}}]));
    $res = $ua->request($req);
    is($res->code, 200, _get_request_test_message("PATCH test voucher"));
    $req = HTTP::Request->new('GET', $voucher_uri);
    $res = $ua->request($req);
    is($res->code, 200, _get_request_test_message("fetch PATCH test voucher"));
    my $patch_voucher = JSON::from_json($res->decoded_content);
    delete $patch_voucher->{_links};
    $voucher_id = delete $patch_voucher->{id};
    is_deeply($voucher, $patch_voucher, "check PATCHed voucher against POSTed voucher");


    $req = HTTP::Request->new('POST', $uri.'/api/vouchers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json($put_voucher));
    $res = $ua->request($req);
    is($res->code, 422, _get_request_test_message("POST same voucher code again"));

    $put_voucher->{id} = $voucher_id;

    
#    $req = HTTP::Request->new('PATCH', $billingzone_uri);
#    $req->header('Content-Type' => 'application/json-patch+json');
#    $req->header('Prefer' => 'return=representation');
#    $req->content(JSON::to_json(
#        [ { op => 'replace', path => '/zone', value => 'AT' } ]
#    ));
#    $res = $ua->request($req);
#    is($res->code, 200, _get_request_test_message("PATCH test billingzone"));
#    $req = HTTP::Request->new('GET', $billingzone_uri);
#    $res = $ua->request($req);
#    is($res->code, 200, _get_request_test_message("fetch PATCHed test billingzone"));
#    $billingzone = JSON::from_json($res->decoded_content);


    # mysql has an issue with datetime overruns,check for max date
    $req = HTTP::Request->new('PATCH', $voucher_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/valid_until', value => '2099-01-01 00:00:00' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, _get_request_test_message("PATCH too far valid_until in voucher"));

    $req = HTTP::Request->new('DELETE', $voucher_uri);
    $res = $ua->request($req);
    is($res->code, 204, _get_request_test_message("delete POSTed test voucher"));
    $req = HTTP::Request->new('GET', $voucher_uri);
    $res = $ua->request($req);
    is($res->code, 404, _get_request_test_message("fetch DELETEd test voucher"));
}

sub _to_json {
    return $json->encode(shift);
}

sub _from_json {
    return $json->decode(shift);
}

sub _get_request_test_message {
    my ($message) = @_;
    my $code = $res->code;
    if ($code == 200 || $code == 201 || $code == 204) {
        return $message;
    } else {
        my $error_content = _from_json($res->content);
        if (defined $error_content && defined $error_content->{message}) {
            return $message . ' (' . $res->message . ': ' . $error_content->{message} . ')';
        } else {
            return $message . ' (' . $res->message . ')';
        }
    }
}

# vim: set tabstop=4 expandtab:
