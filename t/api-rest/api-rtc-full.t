use warnings;
use strict;

use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;
use URI::Escape qw();

#use LWP::Debug;

my $is_local_env = 0;

unless ($ENV{TEST_RTC}) {
    plan skip_all => "not testing rtc, enable TEST_RTC=yes to run tests";
    exit 0;
}

my $domain_id = $ENV{TEST_RTC_DOMAIN_ID} // 3;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my ($netloc) = ($uri =~ m!^https?://(.*)/?.*$!);

my ($ua, $req, $res, $data);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
my $user = $ENV{API_USER} // 'administrator';
my $pass = $ENV{API_PASS} // 'administrator';
$ua->credentials($netloc, "api_admin_http", $user, $pass);


my ($contract_id, $reseller_id, $customer_id, $bprof_id, $customercontact_id, $network_tag);
{
    $req = HTTP::Request->new('POST', $uri.'/api/contracts/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        contact_id => 2,
        status => 'active',
        type => 'reseller',
        billing_profile_id => 1,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST create contract");
    ($contract_id) = $res->header('Location') =~ m!/(\d+)$!;
    ok($contract_id, "got contract_id") || die "we dont't continue here";

    $req = HTTP::Request->new('POST', $uri.'/api/resellers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        contract_id => $contract_id,
        name => 'rtc test reseller ' . time,
        enable_rtc => JSON::true,
        status => 'active',
        rtc_networks => ['sip'],
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST create reseller");
    ($reseller_id) = $res->header('Location') =~ m!/(\d+)$!;
    ok($reseller_id, "got reseller_id")  || die "we dont't continue here";

    $req = HTTP::Request->new('GET', $uri . "/api/resellers/$reseller_id");
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed reseller");
    $data = JSON::from_json($res->decoded_content);
    ok($data->{enable_rtc}, "reseller has rtc enabled");

    $req = HTTP::Request->new('GET', $uri . "/api/rtcnetworks/$reseller_id");
    $res = $ua->request($req);
    is($res->code, 200, "fetch rtcnetworks");
    $data = JSON::from_json($res->decoded_content);
    is($data->{networks}[0]{connector}, 'sip-connector', "rtcnetwork exists");
    $network_tag = $data->{networks}[0]{tag};

    diag("reseller id: $reseller_id , network_tag: $network_tag");

    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => 'rtc test bprof ' . time,
        handle => 'rtc_test_bprof_' . time,
        reseller_id => $reseller_id,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST create billingprofile");
    ($bprof_id) = $res->header('Location') =~ m!/(\d+)$!;
    ok($bprof_id, "got bprof_id")  || die "we dont't continue here";

    $req = HTTP::Request->new('POST', $uri.'/api/customercontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        email => 'rtccustomer@ngcp.com',
        reseller_id => $reseller_id,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST create customercontact");
    ($customercontact_id) = $res->header('Location') =~ m!/(\d+)$!;
    ok($customercontact_id, "got customercontact_id")  || die "we dont't continue here";

    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        contact_id => $customercontact_id,
        billing_profile_id => $bprof_id,
        reseller_id => $reseller_id,
        status => 'active',
        type => 'sipaccount',
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST create customer");
    ($customer_id) = $res->header('Location') =~ m!/(\d+)$!;
    ok($customer_id, "got customer_id")  || die "we dont't continue here";

    diag("customer id: $customer_id");
}

my ($sub1_id, $sub1_name, $sub2_id, $sub2_name);
{
    $sub1_name = 'rtcsub' .int(rand(1000));
    $sub2_name = 'rtcsub' .int(rand(1000));

    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        customer_id => $customer_id,
        domain_id => $domain_id,
        username => $sub1_name,
        password => $sub1_name,
        webusername => $sub1_name,
        webpassword => $sub1_name,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST create subscriber 1");
    ($sub1_id) = $res->header('Location') =~ m!/(\d+)$!;
    ok($sub1_id, "got sub1_id")  || die "we dont't continue here";

    $req = HTTP::Request->new('PATCH', $uri."/api/subscriberpreferences/$sub1_id");
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json([
            {op => 'add', path => '/use_rtpproxy', value => 'never'},
        ]));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH set subscriberpreferences sub1");

    diag("subscriber $sub1_name: $sub1_id");

    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        customer_id => $customer_id,
        domain_id => $domain_id,
        username => $sub2_name,
        password => $sub2_name,
        webusername => $sub2_name,
        webpassword => $sub2_name,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST create subscriber 2");
    ($sub2_id) = $res->header('Location') =~ m!/(\d+)$!;
    ok($sub2_id, "got sub2_id")  || die "we dont't continue here";

    $req = HTTP::Request->new('PATCH', $uri."/api/subscriberpreferences/$sub2_id");
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json([
            {op => 'add', path => '/use_rtpproxy', value => 'never'},
        ]));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH set subscriberpreferences sub2");

    diag("subscriber $sub2_name: $sub2_id");
}

done_testing;