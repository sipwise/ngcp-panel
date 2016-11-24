#use Sipwise::Base;
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

my %subscriber_map = ();
my %customer_map = ();

{
    my $customer = _create_customer(
        type => "sipaccount",
        #is_pbx_pilot => JSON::true,
        );
    my $subscriber = _create_subscriber($customer,
        #is_pbx_pilot => JSON::true,
        primary_number => { cc => 888, ac => '1'.(scalar keys %subscriber_map), sn => $t },
        );

    my $call_forwards = set_callforwards($subscriber,{ cfu => {
                destinations => [
                    { destination => "5678" },
                    { destination => "autoattendant", },
                ],
            }});
    $call_forwards = set_callforwards($subscriber,{ cfu => {
                destinations => [
                    { destination => "5678" },
                    #{ destination => "autoattendant", },
                ],
            }});
}

sub set_callforwards {
    my ($subscriber,$call_forwards) = @_;

    my $callforward_uri = $uri.'/api/callforwards/'.$subscriber->{id};
    $req = HTTP::Request->new('PUT', $callforward_uri); #$customer->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json($call_forwards));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test callforwards");
    $req = HTTP::Request->new('GET', $callforward_uri); # . '?page=1&rows=' . (scalar keys %$put_data));
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test callforwards");
    return JSON::from_json($res->decoded_content);

}

sub _get_subscriber {

    my ($subscriber) = @_;
    $req = HTTP::Request->new('GET', $uri.'/api/subscribers/'.$subscriber->{id});
    $res = $ua->request($req);
    is($res->code, 200, "fetch test subscriber");
    $subscriber = JSON::from_json($res->decoded_content);
    $subscriber_map{$subscriber->{id}} = $subscriber;
    return $subscriber;

}

sub _create_subscriber {

    my ($customer,@further_opts) = @_;
    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        domain_id => $domain->{id},
        username => 'subscriber_' . (scalar keys %subscriber_map) . '_'.$t,
        password => 'subscriber_password',
        customer_id => $customer->{id},
        #status => "active",
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create test subscriber");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch test subscriber");
    my $subscriber = JSON::from_json($res->decoded_content);
    $subscriber_map{$subscriber->{id}} = $subscriber;
    return $subscriber;

}

sub _update_subscriber {

    my ($subscriber,@further_opts) = @_;
    $req = HTTP::Request->new('PUT', $uri.'/api/subscribers/'.$subscriber->{id});
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        %$subscriber,
        @further_opts,
    }));
    $res = $ua->request($req);
    is($res->code, 200, "patch test subscriber");
    $subscriber = JSON::from_json($res->decoded_content);
    $subscriber_map{$subscriber->{id}} = $subscriber;
    return $subscriber;

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
