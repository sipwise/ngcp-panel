use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;
use Storable qw();
use URI::Escape qw();

use JSON::PP;
use LWP::Debug;

my $is_local_env = 1;

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
    $ua->credentials("127.0.0.1:4443", "api_admin_http", 'administrator', 'administrator');
    #$ua->timeout(500); #useless, need to change the nginx timeout
} else {
    $ua->ssl_opts(
        SSL_cert_file => $valid_ssl_client_cert,
        SSL_key_file  => $valid_ssl_client_key,
        SSL_ca_file   => $ssl_ca_cert,
    );    
}


# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/profilepackages/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-profilepackages", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}


my $t = time;
my $default_reseller_id = 1;

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test profile $t",
    handle  => "testprofile$t",
    reseller_id => $default_reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test billing profile");
my $billingprofile_uri = $uri.'/'.$res->header('Location');
$req = HTTP::Request->new('GET', $billingprofile_uri);
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed billing profile");
my $billingprofile = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test billing network ".$t,
    description  => "test billing network description ".$t,
    reseller_id => $default_reseller_id,
    blocks => [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
               {ip=>'fdfe::5a55:caff:fefa:908a'},
               {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},],
}));
$res = $ua->request($req);
is($res->code, 201, "POST test billingnetwork");
my $billingnetwork_uri = $uri.'/'.$res->header('Location');
$req = HTTP::Request->new('GET', $billingnetwork_uri);
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed billingnetwork");
my $billingnetwork = JSON::from_json($res->decoded_content);

{
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test profile package " . $t,
        description  => "test profile package description " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => [{ profile_id => $billingprofile->{id}, }, ]
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profilepackage");
    my $profilepackage = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('PUT', $profilepackage_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test profile package ".$t." PUT",
        description  => "test profile package description ".$t." PUT",
        #reseller_id => $reseller_id,
        initial_profiles => [{ profile_id => $billingprofile->{id}, }, ],
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test profilepackage");
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test profilepackage");
    $profilepackage = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('PATCH', $profilepackage_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "test profile package ".$t." PATCH" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test profilepackage");
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test profilepackage");
    $profilepackage = JSON::from_json($res->decoded_content);

    $req = HTTP::Request->new('PATCH', $profilepackage_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => "terminated" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "terminate test profilepackage");
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 404, "try to fetch terminated test profilepackage");
    
}

{
    
    my @profile_packages = ();
    
    for (my $i = 1; $i <= 3; $i++) {
        push(@profile_packages,_post_profile_package($i));
    }
    
    $req = HTTP::Request->new('GET', $uri.'/api/profilepackages/?page=1&rows=5&network_name='.URI::Escape::uri_escape('%')."network $t");
    $res = $ua->request($req);
    is($res->code, 200, "filter packages by network name");
    my $collection = JSON::from_json($res->decoded_content);
    is_deeply($collection->{_embedded}->{'ngcp:profilepackages'},[ map { $_->{get}; } @profile_packages ],"compare filtered collection deeply");

}

done_testing;

sub _post_profile_package {

    my ($i) = @_;

    my %test_data = (post => {
        name => "test profile package ".$i . ' ' . $t,
        description  => "test profile package description ".$i . $t,
        reseller_id => $default_reseller_id,
        status => 'active',
        initial_profiles => [{ profile_id => $billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],
        initial_balance => 0.0,
        balance_interval_value => 30,
        balance_interval_unit => 'day',
        balance_interval_start_mode => 'create',
        service_charge => 0.0,
        notopup_discard_intervals => undef,
        carry_over_mode => 'carry_over',
        timely_duration_value => 7,
        timely_duration_unit => 'day',        
        underrun_profile_threshold => 0.0,
        underrun_profiles => [ { profile_id => $billingprofile->{id}, network_id => undef } ],
        underrun_lock_threshold => 0.0,
        underrun_lock_level => 4,
        topup_profiles => [ { profile_id => $billingprofile->{id}, network_id => undef } ],
        topup_lock_level => undef,
    });
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json($test_data{post}));
    $res = $ua->request($req);
    is($res->code, 201, "create test profile package " . $i);
    $test_data{uri} = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $test_data{uri});
    $res = $ua->request($req);
    is($res->code, 200, "fetch test profile package " . $i);
    my $get = JSON::from_json($res->decoded_content);
    $test_data{get} = Storable::dclone($get);
    delete $get->{id};
    delete $get->{_links};
    is_deeply($get,$test_data{post}, "check created profile package $i deeply");
    return \%test_data;

}
