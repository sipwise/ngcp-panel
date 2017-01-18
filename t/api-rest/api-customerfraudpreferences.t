use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $is_local_env = 0;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my ($netloc) = ($uri =~ m!^https?://(.*)/?.*$!);

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
my $user = $ENV{API_USER} // 'administrator';
my $pass = $ENV{API_PASS} // 'administrator';
$ua->credentials($netloc, "api_admin_http", $user, $pass);

#$ua->add_handler("request_send",  sub {
#    my ($request, $ua, $h) = @_;
#    print $request->method . ' ' . $request->uri . "\n" . ($request->content ? $request->content . "\n" : '') unless $request->header('authorization');
#    return undef;
#});
#$ua->add_handler("response_done", sub {
#    my ($response, $ua, $h) = @_;
#    print $response->decoded_content . "\n" if $response->code != 401;
#    return undef;
#});

my $t = time;
my $reseller_id = 1;

$req = HTTP::Request->new('POST', $uri.'/api/domains/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    domain => 'test' . $t . '.example.org',
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test domain");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed test domain");
my $domain = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test profile $t",
    handle  => "testprofile$t",
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "create test billing profile");
my $billing_profile_id = $res->header('Location');
$billing_profile_id =~ s/^.+\/(\d+)$/$1/;

$req = HTTP::Request->new('POST', $uri.'/api/customercontacts/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    firstname => "cust_contact_first",
    lastname  => "cust_contact_last",
    email     => "cust_contact\@custcontact.invalid",
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "create customer contact");
$req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
$res = $ua->request($req);
is($res->code, 200, "fetch customer contact");
my $custcontact = JSON::from_json($res->decoded_content);

my %customer_map = ();

{ #MT18601
    my $customer = _create_customer();



}

sub _create_customer {

    my (@further_opts) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        billing_profile_id => $billing_profile_id,
        max_subscribers => undef,
        external_id => undef,
        #status => "active",
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test customer");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test customer");
    my $customer = JSON::from_json($res->decoded_content);
    $customer_map{$customer->{id}} = $customer;
    return $customer;

}

done_testing;
