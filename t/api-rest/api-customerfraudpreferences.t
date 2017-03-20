#use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my ($ua, $req, $res);
use Test::Collection;
$ua = Test::Collection->new()->ua();

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

#goto SKIP;
{
    my $customer = _create_customer();

    my $customerfraudpreferences_uri = $uri.'/api/customerfraudpreferences/'.$customer->{id};
    $req = HTTP::Request->new('PUT', $customerfraudpreferences_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        fraud_daily_limit => 1,
        fraud_daily_lock => 1,
        fraud_daily_notify =>  'notify_daily_'.$t.'@example.com',
        }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test customerfraudpreferences");
    $req = HTTP::Request->new('GET', $customerfraudpreferences_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test customerfraudpreferences");
    my $customerfraudpreferences = JSON::from_json($res->decoded_content);
    delete $customerfraudpreferences->{_links};

    is_deeply($customerfraudpreferences,{
        fraud_interval_limit => undef,
        fraud_interval_lock => undef,
        fraud_interval_notify =>  undef,
        fraud_daily_limit => 1,
        fraud_daily_lock => 1,
        fraud_daily_notify =>  'notify_daily_'.$t.'@example.com',
    },"check PUT test customerfraudpreferences (created) deeply");

    $req = HTTP::Request->new('PUT', $customerfraudpreferences_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        fraud_interval_limit => 2,
        fraud_interval_lock => 2,
        fraud_interval_notify =>  'notify_interval_'.$t.'@example.com',
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test customerfraudpreferences");
    $req = HTTP::Request->new('GET', $customerfraudpreferences_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test customerfraudpreferences");
    $customerfraudpreferences = JSON::from_json($res->decoded_content);
    delete $customerfraudpreferences->{_links};

    is_deeply($customerfraudpreferences,{
        fraud_interval_limit => 2,
        fraud_interval_lock => 2,
        fraud_interval_notify =>  'notify_interval_'.$t.'@example.com',
        fraud_daily_limit => 1,
        fraud_daily_lock => 1,
        fraud_daily_notify =>  'notify_daily_'.$t.'@example.com',
    },"check PUT test customerfraudpreferences (updated) deeply");

}

$t++;

#SKIP:
{
    my $customer = _create_customer();

    my $customerfraudpreferences_uri = $uri.'/api/customerfraudpreferences/'.$customer->{id};
    $req = HTTP::Request->new('PATCH', $customerfraudpreferences_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/fraud_daily_limit', value => '1' },
          { op => 'replace', path => '/fraud_daily_lock', value => '1' },
          { op => 'replace', path => '/fraud_daily_notify', value => 'notify_daily_'.$t.'@example.com' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test customerfraudpreferences");
    $req = HTTP::Request->new('GET', $customerfraudpreferences_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test customerfraudpreferences");
    my $customerfraudpreferences = JSON::from_json($res->decoded_content);
    delete $customerfraudpreferences->{_links};

    is_deeply($customerfraudpreferences,{
        fraud_interval_limit => undef,
        fraud_interval_lock => undef,
        fraud_interval_notify =>  undef,
        fraud_daily_limit => 1,
        fraud_daily_lock => 1,
        fraud_daily_notify =>  'notify_daily_'.$t.'@example.com',
    },"check PATCHED test customerfraudpreferences (created) deeply");

    $req = HTTP::Request->new('PATCH', $customerfraudpreferences_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/fraud_interval_limit', value => '2' },
          { op => 'replace', path => '/fraud_interval_lock', value => '2' },
          { op => 'replace', path => '/fraud_interval_notify', value => 'notify_interval_'.$t.'@example.com' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test customerfraudpreferences");
    $req = HTTP::Request->new('GET', $customerfraudpreferences_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHED test customerfraudpreferences");
    $customerfraudpreferences = JSON::from_json($res->decoded_content);
    delete $customerfraudpreferences->{_links};

    is_deeply($customerfraudpreferences,{
        fraud_interval_limit => 2,
        fraud_interval_lock => 2,
        fraud_interval_notify =>  'notify_interval_'.$t.'@example.com',
        fraud_daily_limit => 1,
        fraud_daily_lock => 1,
        fraud_daily_notify =>  'notify_daily_'.$t.'@example.com',
    },"check PATCHED test customerfraudpreferences (updated) deeply");

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
