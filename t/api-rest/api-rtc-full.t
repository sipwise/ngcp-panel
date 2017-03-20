use warnings;
use strict;

use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;
use URI::Escape qw();

#use LWP::Debug;

my $is_local_env = 0;

unless ($ENV{TEST_RTC}) {
    plan skip_all => "not testing rtc, enable TEST_RTC=yes to run tests";
    exit 0;
}

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $domain_name = $ENV{TEST_RTC_DOMAIN};
unless ($domain_name) {
    ($domain_name) = ($uri =~ m!^https?://([^/:]*)(:[0-9]+)?/?.*$!);
}

my ($ua, $req, $res, $data);

use Test::Collection;
$ua = Test::Collection->new()->ua();

my ($domain_id);
{
    $req = HTTP::Request->new('GET', "$uri/api/domains/?domain=$domain_name");
    $res = $ua->request($req);
    is($res->code, 200, "GET search domain");
    $data = JSON::from_json($res->decoded_content);
    ok($data->{total_count}, "got at least one domain") || die "we can't continue without domain";

    my $selected_domain = ( 'ARRAY' eq ref $data->{_embedded}{'ngcp:domains'} )
            ? $data->{_embedded}{'ngcp:domains'}[0]
            : $data->{_embedded}{'ngcp:domains'};

    $domain_id = $selected_domain->{id};
    $domain_name = $selected_domain->{domain};

    diag("domain: $selected_domain->{domain} ($domain_id)");
}

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
        rtc_networks => ['sip','xmpp','webrtc'],
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

    diag("reseller id: $reseller_id , first network_tag: $network_tag");

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

    diag("subscriber $sub1_name\@$domain_name (pass: $sub1_name, id: $sub1_id)");

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

    diag("subscriber $sub2_name\@$domain_name (pass: $sub2_name, id: $sub2_id)");
    diag("you can now create new session using:");
    my $noport_uri = ($uri =~ s/:[0-9]+//r);
    diag("    curl -XPOST -v -k --user $sub1_name\@$domain_name:$sub1_name -H'Content-Type: application/json' $noport_uri/api/rtcsessions/ --data-binary '{}'");
    diag("    curl -XPOST -v -k --user $sub2_name\@$domain_name:$sub2_name -H'Content-Type: application/json' $noport_uri/api/rtcsessions/ --data-binary '{}'");
}

done_testing;
