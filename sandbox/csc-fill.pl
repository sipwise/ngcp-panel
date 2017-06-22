#!/usr/bin/perl

use strict;
use warnings;

use lib '../t/lib';

use JSON qw();
use Data::Dumper;

my $uri = $ENV{CATALYST_SERVER};
my ($ua, $req, $res);

use Test::Collection;
$ua = Test::Collection->new()->ua();

my $reseller_id = 1;
my $t = time;

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test profile $t",
    handle  => "testprofile$t",
    reseller_id => $reseller_id,
}));
$res = $ua->request($req);
die "Failed to create billing profile\n" unless($res->is_success);
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
die "Failed to create customer contact\n" unless($res->is_success);
my $customer_contact_id = $res->header('Location');
$customer_contact_id =~ s/^.+\/(\d+)$/$1/;

$req = HTTP::Request->new('POST', $uri.'/api/customers/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    status => "active",
    contact_id => $customer_contact_id,
    type => "sipaccount",
    billing_profile_id => $billing_profile_id,
    max_subscribers => 10,
    external_id => undef,
}));
$res = $ua->request($req);
die "Failed to create customer\n" unless($res->is_success);
my $customer_id = $res->header('Location');
$customer_id =~ s/^.+\/(\d+)$/$1/;

$req = HTTP::Request->new('POST', $uri.'/api/domains/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    reseller_id => $reseller_id,
    domain => time.'.example.org',
}));
$res = $ua->request($req);
die "Failed to create domain\n" unless($res->is_success);
my $domain_id = $res->header('Location');
$domain_id =~ s/^.+\/(\d+)$/$1/;

$req = HTTP::Request->new('POST', $uri.'/api/subscribers/');
$req->header('Content-Type' => 'application/json');
$req->content(JSON::to_json({
    customer_id => $customer_id,
    username => $t.'_csctestuser',
    password => 'password',
    webusername => $t.'_csctestuser',
    webpassword => 'password',
    domain_id => $domain_id,
}));
$res = $ua->request($req);
die "Failed to create subscriber\n" unless($res->is_success);
my $subscriber_id = $res->header('Location');
$subscriber_id =~ s/^.+\/(\d+)$/$1/;


