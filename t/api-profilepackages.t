use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;
use Storable qw();

use JSON::PP;
use LWP::Debug;

#BEGIN {
#    unshift(@INC,'../lib');
#}
#use NGCP::Panel::Utils::BillingNetworks qw();

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
#my $billingnetwork = test_billingnetwork_journal($t,$default_reseller_id);

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
    #test_profilepackages_journal($t,$default_reseller_id,$billingnetwork->{id});
    
    my @profile_packages = ();
    
    for (my $i = 1; $i <= 3; $i++) {
        push(@profile_packages,_post_profile_package($i,$default_reseller_id));
    }
    
    #my $ipv4blocks = [{ip=>'10.0.4.7',mask=>26}, #0..63
    #                  {ip=>'10.0.4.99',mask=>26}, #64..127
    #                  {ip=>'10.0.5.9',mask=>24},
    #                    {ip=>'10.0.6.9',mask=>24},];
    #for (my $i = 0; $i < 3; $i++) {
    #    push(@billing_networks,_post_billing_network($ipv4blocks,'ipv4',$i,$default_reseller_id));
    #}
    #my $t2 = time;
    #
    #diag("time: " . ($t2 - $t1));
    #
    $req = HTTP::Request->new('GET', $uri.'/api/profilepackages/?page=1&rows=5&network_name='."%network $t");
    $res = $ua->request($req);
    is($res->code, 200, "blah");
    my $blah = JSON::from_json($res->decoded_content);
    print $blah;
    ##my $nexturi = $uri.'/api/customers/?page=1&rows=5&status=active';
    ##do {
    ##    $res = $ua->get($nexturi);
    ##    is($res->code, 200, "fetch contacts page");
    ##    my $collection = JSON::from_json($res->decoded_content);
    ##    my $selfuri = $uri . $collection->{_links}->{self}->{href};
    ##    is($selfuri, $nexturi, "check _links.self.href of collection");
    ##    my $colluri = URI->new($selfuri);    
    ##
    ##
    ##post_billing_network({
    ##        name => "test billing network 0",
    ##        description  => "test billing network description 0",
    ##        reseller_id => $default_reseller_id,
    ##        blocks => $blocks,
    ##    });
    ##is($res->code, 500, "create test billingnetwork with duplicate name");
    ##my $billingnetwork_uri = $uri.'/'.$res->header('Location');    


    

}





done_testing;

sub _post_profile_package {

    my ($i,$reseller_id) = @_;

    my %test_data = (post => {
        name => "test profile package ".$i . ' ' . $t,
        description  => "test profile package description ".$i . $t,
        #reseller_id => $reseller_id,
        status => 'active',
        initial_profiles => [{ profile_id => $billingprofile->{id}, }, #network_id => $billingnetwork->{id}
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],
        #underrun_profiles => $underrun_profiles,
        #topup_profiles => $underrun_profiles,
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














sub test_profilepackages_journal {
    my ($t,$reseller_id,$profile_id) = @_;
    
    my $blocks = [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
                    {ip=>'fdfe::5a55:caff:fefa:908a'},
                    {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},];
    
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test profile package " . $t,
        description  => "test profile package description " . $t,
        reseller_id => $reseller_id,
        initial_profiles => [{ profile_id => $profile_id, }, ]
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profilepackage");
    my $profilepackage = JSON::from_json($res->decoded_content);
    
    #_test_item_journal_link('profilepackages',$profilepackage,$profilepackage->{id});
    #_test_journal_options_head('profilepackages',$profilepackage->{id});
    #my $journals = {};
    #my $journal = _test_journal_top_journalitem('profilepackages',$profilepackage->{id},$profilepackage,'create',$journals);
    #_test_journal_options_head('profilepackages',$profilepackage->{id},$journal->{id});
    
    $req = HTTP::Request->new('PUT', $profilepackage_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test profile package ".$t." PUT",
        description  => "test profile package description ".$t." PUT",
        #reseller_id => $reseller_id,
        initial_profiles => [{ profile_id => $profile_id, }, ],
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test profilepackage");
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test profilepackage");
    $profilepackage = JSON::from_json($res->decoded_content);
    
    #_test_item_journal_link('profilepackages',$profilepackage,$profilepackage->{id});    
    #$journal = _test_journal_top_journalitem('profilepackages',$profilepackage->{id},$profilepackage,'update',$journals,$journal);
    
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

    #_test_item_journal_link('profilepackages',$profilepackage,$profilepackage->{id});    
    #$journal = _test_journal_top_journalitem('profilepackages',$profilepackage->{id},$profilepackage,'update',$journals,$journal);

    #_test_journal_collection('profilepackages',$profilepackage->{id},$journals);
    
    return $profilepackage;
    
}






