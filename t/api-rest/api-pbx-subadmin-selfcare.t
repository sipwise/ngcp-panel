use strict;
use warnings;

use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;
use Test::ForceArray qw/:all/;

use DateTime qw();
use DateTime::Format::Strptime qw();
use DateTime::Format::ISO8601 qw();

use Data::Dumper;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my $suri = $uri; $suri =~ s/:\d443/:443/;
my $sub_domain = $suri;
$sub_domain =~ s/^https?:\/\///;
$sub_domain =~ s/:\d+$//;
my ($ua, $req, $res);

use Test::Collection;
$ua = Test::Collection->new()->ua();

my $t = time;
my $reseller_id = 1;

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
# TODO: get id from body once the API returns it
my $billing_profile_id = $res->header('Location');
$billing_profile_id =~ s/^.+\/(\d+)$/$1/;

# fetch a system contact for later tests
$req = HTTP::Request->new('GET', $uri.'/api/systemcontacts/?page=1&rows=1');
$res = $ua->request($req);
is($res->code, 200, "fetch system contacts");
my $sysct = JSON::from_json($res->decoded_content);
my $system_contact_id = get_embedded_item($sysct, 'systemcontacts')->{id};

# first, create a contact
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

# create a customer without selfcare flag
$req = HTTP::Request->new('POST', $uri.'/api/customers/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    status => "active",
    contact_id => $custcontact->{id},
    type => "sipaccount",
    billing_profile_id => $billing_profile_id,
    max_subscribers => undef,
    external_id => 'nonselfadmin_'.$t,
    type => 'pbxaccount',
}));
$res = $ua->request($req);
is($res->code, 201, "create test customer without selfcare flag");
my $nonself_customer_id = $res->header('Location');
$nonself_customer_id =~ s/^.+\/(\d+)$/$1/;

# create a customer with selfcare flag
$req = HTTP::Request->new('POST', $uri.'/api/customers/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    status => "active",
    contact_id => $custcontact->{id},
    type => "sipaccount",
    billing_profile_id => $billing_profile_id,
    max_subscribers => undef,
    external_id => 'selfadmin_'.$t,
    type => 'pbxaccount',
    subadmin_selfadmin => 1,
}));
$res = $ua->request($req);
is($res->code, 201, "create test customer with selfcare flag");
my $self_customer_id = $res->header('Location');
$self_customer_id =~ s/^.+\/(\d+)$/$1/;

# fetch or create a domain for our subscribers
$req = HTTP::Request->new('POST', $uri.'/api/domains/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    reseller_id => $reseller_id,
    domain => $sub_domain,
}));
$res = $ua->request($req);
my $domain_id;
if($res->code eq 422) {
    my $r = JSON::from_json($res->decoded_content);
    if($r->{message} =~ /already exists/) {
        $req = HTTP::Request->new('GET', $uri.'/api/domains/?domain='.$sub_domain);
        $res = $ua->request($req);
        is($res->code, 200, "fetching existing domain $sub_domain");
        my $r = JSON::from_json($res->decoded_content);
        is($r->{total_count}, 1, "check for singlular existence of domain $sub_domain");
        $domain_id = $r->{_embedded}->{'ngcp:domains'}->[0]->{id};
        ok($domain_id =~ /^\d+$/, "check for numberical domain id");
    } else {
        is($res->code, 201, "create test domain $sub_domain");
    }
} else {
    is($res->code, 201, "create test domain $sub_domain");
    $domain_id = $res->header('Location');
    $domain_id =~ s/^.+\/(\d+)$/$1/;
}

# create admin user in nonself-customer
$req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    administrative => 1,
    customer_id => $nonself_customer_id,
    display_name => 'Pilot Admin',
    domain_id => $domain_id,
    is_pbx_pilot => 1,
    primary_number => { cc => '43', ac => '0', sn => $t.'00000' },
    alias_numbers => [
        { cc => '43', ac => '0', sn => $t.'00001' },
        { cc => '43', ac => '0', sn => $t.'00002' },
        { cc => '43', ac => '0', sn => $t.'00003' },
        { cc => '43', ac => '0', sn => $t.'00004' },
    ],
    username => 'nonself_testpilot_'.$t,
    password => 'password',
    webusername => 'nonself_testpilot_'.$t,
    webpassword => 'webpassword'
}));
$res = $ua->request($req);
is($res->code, 201, "create pilot admin in test customer without selfcare flag");

# create admin user in self-customer
$req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    administrative => 1,
    customer_id => $self_customer_id,
    display_name => 'Pilot Admin',
    domain_id => $domain_id,
    is_pbx_pilot => 1,
    primary_number => { cc => '43', ac => '1', sn => $t.'00000' },
    alias_numbers => [
        { cc => '43', ac => '1', sn => $t.'00001' },
        { cc => '43', ac => '1', sn => $t.'00002' },
        { cc => '43', ac => '1', sn => $t.'00003' },
        { cc => '43', ac => '1', sn => $t.'00004' },
    ],
    username => 'self_testpilot_'.$t,
    password => 'password',
    webusername => 'self_testpilot_'.$t,
    webpassword => 'webpassword'
}));
$res = $ua->request($req);
is($res->code, 201, "create pilot admin in test customer with selfcare flag");

# create UA for nonself-subadmin
my $nsua = Test::Collection->new(
    subscriber_user => 'nonself_testpilot_'.$t.'@'.$sub_domain,
    subscriber_pass => 'webpassword',
    runas_role => 'subscriber',
)->runas('subscriber', $suri)->ua();

# create UA for self-subadmin
my $sua = Test::Collection->new(
    subscriber_user => 'self_testpilot_'.$t.'@'.$sub_domain,
    subscriber_pass => 'webpassword',
    runas_role => 'subscriber',
)->runas('subscriber', $suri)->ua();

{
    # use nonself-subadmin to perform operations:

    $req = HTTP::Request->new('GET', $suri.'/api/subscribers/');
    $res = $nsua->request($req);
    is($res->code, 200, "fetch all subscribers with non-selfcare subadmin");
    my $subs = JSON::from_json($res->decoded_content);
    is($subs->{total_count}, 1, "check if total count is 1 for non-selfcare subadmin");

    # trying to create extension
    $req = HTTP::Request->new('POST', $suri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        administrative => 0,
        customer_id => $nonself_customer_id,
        display_name => 'My Ext',
        domain_id => $domain_id,
        pbx_extension => '101',
        alias_numbers => [
            { cc => '43', ac => '0', sn => $t.'00001' },
        ],
        username => 'self_testext101_'.$t,
        password => 'password',
        webusername => 'self_testext101_'.$t,
        webpassword => 'webpassword'
    }));
    $res = $nsua->request($req);
    is($res->code, 403, "create extension in test customer without selfcare using subadmin");

    # trying to create group
    $req = HTTP::Request->new('POST', $suri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        administrative => 0,
        customer_id => $nonself_customer_id,
        display_name => 'My Group',
        domain_id => $domain_id,
        pbx_extension => '100',
        is_pbx_group => 1,
        alias_numbers => [
            { cc => '43', ac => '0', sn => $t.'00002' },
        ],
        username => 'self_testgrp100_'.$t,
        password => 'password',
        webusername => 'self_testgrp100_'.$t,
        webpassword => 'webpassword'
    }));
    $res = $nsua->request($req);
    is($res->code, 403, "create group in test customer without selfcare using subadmin");

    # create another extension using admin
    $req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        administrative => 0,
        customer_id => $nonself_customer_id,
        display_name => 'My Ext',
        domain_id => $domain_id,
        pbx_extension => '101',
        alias_numbers => [
            { cc => '43', ac => '0', sn => $t.'00001' },
        ],
        username => 'self_testext101_'.$t,
        password => 'password',
        webusername => 'self_testext101_'.$t,
        webpassword => 'webpassword'
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create extension in test customer without selfcare using admin");
    my $ext = JSON::from_json($res->decoded_content);

    # check again with subadmin, this time we should get 2 subs
    $req = HTTP::Request->new('GET', $suri.'/api/subscribers/');
    $res = $nsua->request($req);
    is($res->code, 200, "fetch all subscribers after ext creation with non-selfcare subadmin");
    $subs = JSON::from_json($res->decoded_content);
    is($subs->{total_count}, 2, "check if total count is 2 after ext creation for non-selfcare subadmin");

   
    # TODO: test if access to ext is rejected
    # - voicemail, fax, prefs, calllist, ...
}

{
    # use self-subadmin to perform operations:

    $req = HTTP::Request->new('GET', $suri.'/api/subscribers/');
    $res = $sua->request($req);
    is($res->code, 200, "fetch all subscribers with selfcare subadmin");
    my $subs = JSON::from_json($res->decoded_content);
    is($subs->{total_count}, 1, "check if total count is 1 for selfcare subadmin");

    # TODO: test if wrong customer_id is rejected
    # TODO: test if creating another pilot is rejected
    # TODO: test if creating/modifying group works
    # TODO: test if creating/modifying ext works
    # TODO: test if moving numbers from pilot to ext works
    # TODO: test if access to ext works
    # - voicemail, fax, prefs, calllist, ...
}

# TODO: test extension access


done_testing;

# vim: set tabstop=4 expandtab:
