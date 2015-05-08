use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;
use Storable qw();
use URI::Escape qw();

use JSON::PP;
use LWP::Debug;

BEGIN {
    unshift(@INC,'../lib');
}
use NGCP::Panel::Utils::BillingNetworks qw();

my $is_local_env = 0;

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

{
    my $blocks = [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
                        {ip=>'fdfe::5a55:caff:fefa:908a'},
                        {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},];
    ok(NGCP::Panel::Utils::BillingNetworks::set_blocks_from_to($blocks),'check if distinct ipv6 addresses are accepted');

    $blocks = [{ip=>'10.0.5.9',mask=>24},
                        {ip=>'10.0.6.9',mask=>24},];
    ok(NGCP::Panel::Utils::BillingNetworks::set_blocks_from_to($blocks),'check if non-overlapping ipv4 subnets are accepted');
    
    if (NGCP::Panel::Utils::BillingNetworks::_CHECK_BLOCK_OVERLAPS) {
        $blocks = [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
                            {ip=>'fdfe::5a55:caff:fefa:9089'},];
        ok(!NGCP::Panel::Utils::BillingNetworks::set_blocks_from_to($blocks),'check if identical ipv6 addresses are detected');
        
     
        $blocks = [{ip=>'10.0.5.9',mask=>24},
                            {ip=>'10.0.5.9',mask=>26},];
        ok(!NGCP::Panel::Utils::BillingNetworks::set_blocks_from_to($blocks),'check if overlapping ipv4 subnets are detected');
        #NGCP::Panel::Utils::BillingNetworks::set_blocks_from_to([{ip=>'fdfe::5a55:caff:fefa:9089',mask=>127},
        #                    {ip=>'fdfe::5a55:caff:fefa:908a',mask=>128},
        #                    {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},]);
        #NGCP::Panel::Utils::BillingNetworks::set_blocks_from_to([{ip=>'10.0.5.9',mask=>24},
        #                    {ip=>'10.0.5.9',mask=>32},]);
    } else {
        diag("subnet overlap checking disabled");
    }

}

# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/billingnetworks/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-billingnetworks", "check Accept-Post header in options response");
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

{
    my $blocks = [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
                    {ip=>'fdfe::5a55:caff:fefa:908a'},
                    {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},];
    
    $req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test billing network ".($t-1),
        description  => "test billing network description ".($t-1),
        reseller_id => $default_reseller_id,
        blocks => $blocks,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test billingnetwork");
    my $billingnetwork_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $billingnetwork_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed billingnetwork");
    my $billingnetwork = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('PUT', $billingnetwork_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test billing network ".($t-1)." PUT",
        description  => "test billing network description ".($t-1)." PUT",
        reseller_id => $default_reseller_id,
        blocks => $blocks,
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test billingnetwork");
    $req = HTTP::Request->new('GET', $billingnetwork_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test billingnetwork");
    $billingnetwork = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('PATCH', $billingnetwork_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "test billing network ".($t-1)." PATCH" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test billingnetwork");
    $req = HTTP::Request->new('GET', $billingnetwork_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test billingnetwork");
    $billingnetwork = JSON::from_json($res->decoded_content);

    $req = HTTP::Request->new('PATCH', $billingnetwork_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => "terminated" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "terminate test billingnetwork");
    $req = HTTP::Request->new('GET', $billingnetwork_uri);
    $res = $ua->request($req);
    is($res->code, 404, "try to fetch terminated test billingnetwork");

}

{
    my @ipv6_billing_networks = ();
    
    #my $t1 = time;
    
    my $ipv6blocks = [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
                    {ip=>'fdfe::5a55:caff:fefa:908a',mask=>undef},
                    {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},];
    for (my $i = 0; $i < scalar @$ipv6blocks; $i++) {
        push(@ipv6_billing_networks,_post_billing_network([ $ipv6blocks->[$i] ],'ipv6',$i+1,$default_reseller_id));
    }
    push(@ipv6_billing_networks,_post_billing_network($ipv6blocks,'ipv6',(scalar @$ipv6blocks)+1,$default_reseller_id));
    
    my @ipv4_billing_networks = ();
    
    my $ipv4blocks = [{ip=>'10.0.4.7',mask=>26}, #0..63
                      {ip=>'10.0.4.99',mask=>26}, #64..127
                      {ip=>'10.0.5.9',mask=>24},
                        {ip=>'10.0.6.9',mask=>24},];
    for (my $i = 0; $i < scalar @$ipv4blocks; $i++) {
        push(@ipv4_billing_networks,_post_billing_network([ $ipv4blocks->[$i] ],'ipv4',$i+1,$default_reseller_id));
    }
    push(@ipv4_billing_networks,_post_billing_network($ipv4blocks,'ipv4',(scalar @$ipv4blocks)+1,$default_reseller_id));
    
    #my $t2 = time;
    #diag("time: " . ($t2 - $t1));
    
    _filter_by_ip("fdfe::5a55:caff:fefa:9089",[ $ipv6_billing_networks[0]->{get},$ipv6_billing_networks[$#ipv6_billing_networks]->{get} ],"ipv6");
    _filter_by_ip("10.0.4.0",[ $ipv4_billing_networks[0]->{get},$ipv4_billing_networks[$#ipv4_billing_networks]->{get} ],"ipv4");
    _filter_by_ip("10.0.4.64",[ $ipv4_billing_networks[1]->{get},$ipv4_billing_networks[$#ipv4_billing_networks]->{get} ],"ipv4");
    _filter_by_ip("10.0.5.255",[ $ipv4_billing_networks[2]->{get},$ipv4_billing_networks[$#ipv4_billing_networks]->{get} ],"ipv4");
    _filter_by_ip("10.0.6.255",[ $ipv4_billing_networks[3]->{get},$ipv4_billing_networks[$#ipv4_billing_networks]->{get} ],"ipv4");

}

done_testing;

sub _filter_by_ip {
    
    my ($ip,$expected,$version) = @_;
    $req = HTTP::Request->new('GET', $uri.'/api/billingnetworks/?page=1&rows=5&ip='.$ip.'&name='.URI::Escape::uri_escape('%').$t);
    $res = $ua->request($req);
    is($res->code, 200, "filter for $version ip ".$ip);
    my $collection = JSON::from_json($res->decoded_content);
    is_deeply($collection->{_embedded}->{'ngcp:billingnetworks'},$expected,"compare filtered collection for $version ip ".$ip." deeply");

}

sub _post_billing_network {

    my ($blocks,$version,$i,$reseller_id) = @_;

    my %test_data = (post => {
        name => "test $version billing network ".$i . ' ' . $t,
        description  => "test $version billing network description ".$i .' '. $t,
        reseller_id => $reseller_id,
        blocks => $blocks,
        status => 'active',
    });
    $req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json($test_data{post}));
    $res = $ua->request($req);
    is($res->code, 201, "create test $version billingnetwork " . $i);
    $test_data{uri} = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $test_data{uri});
    $res = $ua->request($req);
    is($res->code, 200, "fetch test $version billingnetwork " . $i);
    my $get = JSON::from_json($res->decoded_content);
    $test_data{get} = Storable::dclone($get);
    delete $get->{id};
    delete $get->{_links};
    is_deeply($get,$test_data{post}, "check created $version billingnetwork $i deeply");
    return \%test_data;

}
