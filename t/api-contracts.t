# TODO: try to set reseller_id of contact of a system contract, which should fail

use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ssl/ngcp/api/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ssl/ngcp/api/ca-cert.pem";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);

# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/contracts/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-contracts", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
my $t = time;
$req->content(JSON::to_json({
    name => "test profile $t",
    handle  => "testprofile$t",
    reseller_id => 1,
}));
$res = $ua->request($req);
is($res->code, 201, "create test billing profile");
# TODO: get id from body once the API returns it
my $billing_profile_id = $res->header('Location');
$billing_profile_id =~ s/^.+\/(\d+)$/$1/;

# TODO: create customer contact first
my $customer_contact_id = 1;


# collection test
my $firstcontract = undef;
my $syscontact = undef;
my @allcontracts = ();
{
    # first, create a contact
    $req = HTTP::Request->new('POST', $uri.'/api/systemcontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        firstname => "sys_contact_first",
        lastname  => "sys_contact_last",
        email     => "sys_contact\@syscontact.invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create system contact");
    $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch system contact");
    $syscontact = JSON::from_json($res->decoded_content);

    # create 6 new reseller contracts
    my %contracts = ();
    for(my $i = 1; $i <= 6; ++$i) {
        $req = HTTP::Request->new('POST', $uri.'/api/contracts/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            status => "active",
            contact_id => $syscontact->{id},
            type => "reseller",
            billing_profile_id => $billing_profile_id,
        }));
        $res = $ua->request($req);
        is($res->code, 201, "create test reseller contract $i");
        $contracts{$res->header('Location')} = 1;
        push @allcontracts, $res->header('Location');
        $firstcontract = $res->header('Location') unless $firstcontract;
    }

    # try to create invalid contract with wrong type
    $req = HTTP::Request->new('POST', $uri.'/api/contracts/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $syscontact->{id},
        billing_profile_id => $billing_profile_id,
        type => "invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create contract with invalid type");
    my $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'type'/, "check error message in body");

    # try to create invalid contract with wrong billing profile
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $syscontact->{id},
        type => "reseller",
        billing_profile_id => 999999,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create contract with invalid billing profile");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'billing_profile_id'/, "check error message in body");

    # try to create invalid contract with customercontact
    $req->content(JSON::to_json({
        status => "active",
        type => "reseller",
        billing_profile_id => $billing_profile_id,
        contact_id => $customer_contact_id,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create contract with invalid contact");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /The contact_id is not a valid ngcp:systemcontacts item/, "check error message in body");
    
    # try to create invalid contract without contact
    $req->content(JSON::to_json({
        status => "active",
        type => "reseller",
        billing_profile_id => $billing_profile_id,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create contract without contact");

    # try to create invalid contract with invalid status
    $req->content(JSON::to_json({
        type => "reseller",
        billing_profile_id => $billing_profile_id,
        contact_id => $syscontact->{id},
        status => "invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create contract with invalid status");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='status'/, "check error message in body");

    # iterate over contracts collection to check next/prev links and status
    my $nexturi = $uri.'/api/contracts/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        is($res->code, 200, "fetch contacts page");
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        is($selfuri, $nexturi, "check _links.self.href of collection");
        my $colluri = URI->new($selfuri);

        ok($collection->{total_count} > 0, "check 'total_count' of collection");

        my %q = $colluri->query_form;
        ok(exists $q{page} && exists $q{rows}, "check existence of 'page' and 'row' in 'self'");
        my $page = int($q{page});
        my $rows = int($q{rows});
        if($page == 1) {
            ok(!exists $collection->{_links}->{prev}->{href}, "check absence of 'prev' on first page");
        } else {
            ok(exists $collection->{_links}->{prev}->{href}, "check existence of 'prev'");
        }
        if(($collection->{total_count} / $rows) <= $page) {
            ok(!exists $collection->{_links}->{next}->{href}, "check absence of 'next' on last page");
        } else {
            ok(exists $collection->{_links}->{next}->{href}, "check existence of 'next'");
        }

        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri . $collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        # TODO: I'd expect that to be an array ref in any case!
        ok((ref $collection->{_links}->{'ngcp:contracts'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:contracts'} eq "HASH"), "check if 'ngcp:contracts' is array/hash-ref");

        # remove any contact we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:contracts'} eq "HASH") {
            # TODO: handle hashref
            ok($collection->{_embedded}->{'ngcp:contracts'}->{status} ne "terminated", "check if we don't have terminated contracts in response");
            ok($collection->{_embedded}->{'ngcp:contracts'}->{type} eq "sippeering" || $collection->{_embedded}->{'ngcp:contracts'}->{type} eq "reseller", "check for correct system contract type");
            ok(exists $collection->{_embedded}->{'ngcp:contracts'}->{_links}->{'ngcp:systemcontacts'}, "check presence of ngcp:systemcontacts relation");
            ok(exists $collection->{_embedded}->{'ngcp:contracts'}->{_links}->{'ngcp:billingprofiles'}, "check presence of ngcp:billingprofiles relation");
            ok(exists $collection->{_embedded}->{'ngcp:contracts'}->{_links}->{'ngcp:contractbalances'}, "check presence of ngcp:contractbalances relation");
            delete $contracts{$collection->{_links}->{'ngcp:contracts'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:contracts'} }) {
                delete $contracts{$c->{href}};
            }
            foreach my $c(@{ $collection->{_embedded}->{'ngcp:contracts'} }) {
                ok($c->{type} eq "sippeering" || $c->{type} eq "reseller", "check for correct system contract type");
                ok($c->{status} ne "terminated", "check if we don't have terminated contracts in response");
                ok(exists $c->{_links}->{'ngcp:systemcontacts'}, "check presence of ngcp:systemcontacts relation");
                ok(exists $c->{_links}->{'ngcp:billingprofiles'}, "check presence of ngcp:billingprofiles relation");
                ok(exists $c->{_links}->{'ngcp:contractbalances'}, "check presence of ngcp:contractbalances relation");

                delete $contracts{$c->{_links}->{self}->{href}};
            }
        }
             
    } while($nexturi);

    is(scalar(keys %contracts), 0, "check if all test contracts have been found");
}

# test contacts item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstcontract);
    $res = $ua->request($req);
    is($res->code, 200, "check options on item");
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    my $opts = JSON::from_json($res->decoded_content);
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS PUT PATCH )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
    foreach my $opt(qw( POST DELETE )) {
        ok(!grep(/^$opt$/, @hopts), "check for absence of '$opt' in Allow header");
        ok(!grep(/^$opt$/, @{ $opts->{methods} }), "check for absence of '$opt' in body");
    }

    $req = HTTP::Request->new('GET', $uri.'/'.$firstcontract);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one contract item");
    my $contract = JSON::from_json($res->decoded_content);
    ok(exists $contract->{status}, "check existence of status");
    ok(exists $contract->{type}, "check existence of type");
    ok(exists $contract->{billing_profile_id} && $contract->{billing_profile_id}->is_int, "check existence of billing_profile_id");
    ok(exists $contract->{contact_id} && $contract->{contact_id}->is_int, "check existence of contact_id");
    ok(exists $contract->{id} && $contract->{id}->is_int, "check existence of id");
    
    # PUT same result again
    my $old_contract = { %$contract };
    delete $contract->{_links};
    delete $contract->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstcontract);
    
    # check if it fails without content type
    $req->remove_header('Content-Type');
    $req->header('Prefer' => "return=minimal");
    $res = $ua->request($req);
    is($res->code, 415, "check put missing content type");

    # check if it fails with unsupported content type
    $req->header('Content-Type' => 'application/xxx');
    $res = $ua->request($req);
    is($res->code, 415, "check put invalid content type");

    $req->remove_header('Content-Type');
    $req->header('Content-Type' => 'application/json');

    # check if it fails with invalid Prefer
    $req->header('Prefer' => "return=invalid");
    $res = $ua->request($req);
    is($res->code, 400, "check put invalid prefer");

    $req->remove_header('Prefer');
    $req->header('Prefer' => "return=representation");

    # check if it fails with missing body
    $res = $ua->request($req);
    is($res->code, 400, "check put no body");

    # check if put is ok
    $req->content(JSON::to_json($contract));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_contract = JSON::from_json($res->decoded_content);
    is_deeply($old_contract, $new_contract, "check put if unmodified put returns the same");

    # check if we have the proper links
    ok(exists $new_contract->{_links}->{'ngcp:systemcontacts'}, "check put presence of ngcp:systemcontacts relation");
    ok(exists $new_contract->{_links}->{'ngcp:billingprofiles'}, "check put presence of ngcp:billingprofiles relation");
    ok(exists $new_contract->{_links}->{'ngcp:contractbalances'}, "check put presence of ngcp:contractbalances relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstcontract);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'pending' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched contract item");
    my $mod_contact = JSON::from_json($res->decoded_content);
    is($mod_contact->{status}, "pending", "check patched replace op");
    is($mod_contact->{_links}->{self}->{href}, $firstcontract, "check patched self link");
    is($mod_contact->{_links}->{collection}->{href}, '/api/contracts/', "check patched collection link");
    

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef status");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'invalid' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid status");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/contact_id', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid contact_id");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/contact_id', value => $customer_contact_id } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched customer contact_id");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/billing_profile_id', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef billing_profile_id");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/billing_profile_id', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid billing_profile_id");
}

# terminate
{
    # check if deletion of contact fails before terminating the contracts
    $req = HTTP::Request->new('DELETE', $uri.'/'.$syscontact->{_links}->{self}->{href});
    $res = $ua->request($req);
    is($res->code, 423, "check locked status for deleting used contact");

    my $pc;
    foreach my $contract(@allcontracts) {
        $req = HTTP::Request->new('PATCH', $uri.'/'.$contract);
        $req->header('Content-Type' => 'application/json-patch+json');
        $req->header('Prefer' => 'return=representation');
        $req->content(JSON::to_json([
            { "op" => "replace", "path" => "/status", "value" => "terminated" }
        ]));
        $res = $ua->request($req);
        is($res->code, 200, "check termination of contract");
        $pc = JSON::from_json($res->decoded_content);
        is($pc->{status}, "terminated", "check termination status of contract");
    }

    # check if we can still get the terminated contract
    $req = HTTP::Request->new('GET', $uri.'/'.$pc->{_links}->{self}->{href});
    $res = $ua->request($req);
    is($res->code, 404, "check fetching of terminated contract");

    # check if deletion of contact is now ok
    # TODO: are we supposed to be able to delete a contact for a terminated
    # contract? there are still DB contstraints in the way!
    #$req = HTTP::Request->new('DELETE', $uri.'/'.$syscontact->{_links}->{self}->{href});
    #$res = $ua->request($req);
    #is($res->code, 204, "check deletion of unused contact");
}

done_testing;

# vim: set tabstop=4 expandtab:
