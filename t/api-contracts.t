# TODO: try to set reseller_id of contact of a system contract, which should fail

use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

use DateTime qw();
use DateTime::Format::Strptime qw();
use DateTime::Format::ISO8601 qw();

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
#my $customer_contact_id = 1;

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
my $syscontact = JSON::from_json($res->decoded_content);


# collection test
my $firstcontract = undef;
my @allcontracts = ();
{

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
    like($err->{message}, qr/Validation failed.*type/, "check error message in body");

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
        contact_id => $custcontact->{id}, #$customer_contact_id,
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
        is($res->code, 200, "fetch contracts page");
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
    ok(exists $contract->{billing_profiles}, "check existence of billing_profiles");
    is_deeply($contract->{billing_profiles},[ { profile_id => $billing_profile_id, start => undef, stop => undef} ],"check billing_profiles deeply");

    
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
    my $reput_contract = { %$old_contract };
    delete $reput_contract->{billing_profiles};    
    $req->content(JSON::to_json($reput_contract));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_contract = JSON::from_json($res->decoded_content);
    is_deeply($old_contract, $new_contract, "check put if unmodified put returns the same");

    # check if we have the proper links
    ok(exists $new_contract->{_links}->{'ngcp:systemcontacts'}, "check put presence of ngcp:systemcontacts relation");
    ok(exists $new_contract->{_links}->{'ngcp:billingprofiles'}, "check put presence of ngcp:billingprofiles relation");

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
        [ { op => 'replace', path => '/contact_id', value => $custcontact->{id} } ]
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

{
    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "SECOND test profile $t",
        handle  => "second_testprofile$t",
        reseller_id => $reseller_id,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "multi-bill-prof: create another test billing profile");
    # TODO: get id from body once the API returns it
    my $second_billing_profile_id = $res->header('Location');
    $second_billing_profile_id =~ s/^.+\/(\d+)$/$1/;
    
    #$req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    #$req->header('Content-Type' => 'application/json');
    #$req->header('Prefer' => 'return=representation');
    #$req->content(JSON::to_json({
    #    name => "test billing network " . $t,
    #    description  => "test billing network description " . $t,
    #    reseller_id => $reseller_id,
    #    blocks => [{ip=>'10.0.4.7',mask=>26}, #0..63
    #                  {ip=>'10.0.4.99',mask=>26}, #64..127
    #                  {ip=>'10.0.5.9',mask=>24},
    #                    {ip=>'10.0.6.9',mask=>24},],
    #}));
    #$res = $ua->request($req);
    #is($res->code, 201, "multi-bill-prof: create test billingnetwork");
    ## TODO: get id from body once the API returns it
    #my $billingnetwork_uri = $uri.'/'.$res->header('Location');
    #my $billing_network_id = $res->header('Location');
    #$billing_network_id =~ s/^.+\/(\d+)$/$1/;
    
    my $dtf = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    ); #DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );
    my $now = DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local')
    );
    my $t1 = $now->clone->add(days => 1);
    my $t2 = $now->clone->add(days => 2);
    my $t3 = $now->clone->add(days => 3);

    $req = HTTP::Request->new('POST', $uri.'/api/contracts/');
    $req->header('Content-Type' => 'application/json');

    my $data = {
        status => "active",
        contact_id => $syscontact->{id},
        type => "reseller",
        max_subscribers => undef,
        external_id => undef,
    };
    
    my @malformed_profilemappings = ( { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($now),
                                                                stop => $dtf->format_datetime($now),} ]],
                                               code => 422,
                                               msg => "'start' timestamp is not in future"},
                                 { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => undef,
                                                                stop => $dtf->format_datetime($now),},]],
                                               code => 422,
                                               msg => "Interval with 'stop' timestamp but no 'start' timestamp specified"},
                                 { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($t1),
                                                                stop => $dtf->format_datetime($t2),},] , []],
                                               code => 422,
                                               msg => "An interval without 'start' and 'stop' timestamps is required"},                                
                                 { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => undef,
                                                                stop => undef,},
                                                { profile_id => $billing_profile_id,
                                                                start => undef,
                                                                stop => undef,}]],
                                               code => 422,
                                               msg => "Only a single interval without 'start' and 'stop' timestamps is allowed"},                                   
                                 { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => undef,
                                                                stop => undef,},
                                                { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($t1),
                                                                stop => $dtf->format_datetime($t2),},
                                                { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($t1),
                                                                stop => undef,}]],
                                               code => 422,
                                               msg => "Identical 'start' timestamps not allowed"}, 
                                
                                
                                
                                
                                );
    
    foreach my $test (@malformed_profilemappings) {
        foreach my $mappings (@{$test->{mappings}}) {
            $data->{billing_profiles} = $mappings;
            $req->content(JSON::to_json($data));
            $res = $ua->request($req);
            is($res->code, $test->{code}, "multi-bill-prof POST: check " . $test->{msg});
        }
    }
    
    $data->{billing_profiles} = [ { profile_id => $second_billing_profile_id,
                               start => undef,
                               stop => undef, },
                                 { profile_id => $billing_profile_id,
                               start => $dtf->format_datetime($t1),
                               stop => $dtf->format_datetime($t2), },
                                 { profile_id => $billing_profile_id,
                               start => $dtf->format_datetime($t2),
                               stop => $dtf->format_datetime($t3), }];
    $req->content(JSON::to_json($data));
    $res = $ua->request($req);
    is($res->code, 201, "multi-bill-prof: create test contract");
    my $contracturi = $uri.'/'.$res->header('Location');
    
    $req = HTTP::Request->new('GET', $contracturi);
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: fetch contract");
    my $contract = JSON::from_json($res->decoded_content);

    ok(exists $contract->{billing_profile_id}, "multi-bill-prof: check existence of billing_profile_id");
    is($contract->{billing_profile_id}, $second_billing_profile_id,"multi-bill-prof: check if billing_profile_id is correct");    
    ok(exists $contract->{billing_profiles}, "multi-bill-prof: check existence of billing_profiles");
    is_deeply($contract->{billing_profiles},$data->{billing_profiles},"multi-bill-prof: check billing mappings deeply");
    
    
    $req = HTTP::Request->new('PATCH', $contracturi);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');

    @malformed_profilemappings = ( { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($now),
                                                                stop => $dtf->format_datetime($now),} ]],
                                               code => 422,
                                               msg => "'start' timestamp is not in future"},
                                 { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => undef,
                                                                stop => $dtf->format_datetime($now),},]],
                                               code => 422,
                                               msg => "Interval with 'stop' timestamp but no 'start' timestamp specified"},
                                 #{ mappings =>[[ { profile_id => $billing_profile_id,
                                 #                               start => $dtf->format_datetime($t1),
                                 #                               stop => $dtf->format_datetime($t2),},] , []],
                                 #              code => 422,
                                 #              msg => "An interval without 'start' and 'stop' timestamps is required"},                                
                                 { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => undef,
                                                                stop => undef,},
                                                ]],
                                               code => 422,
                                               msg => "Adding intervals without 'start' and 'stop' timestamps is not allowed."},                                   
                                 { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => undef,
                                                                stop => undef,},
                                                { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($t1),
                                                                stop => $dtf->format_datetime($t2),},
                                                { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($t1),
                                                                stop => undef,}]],
                                               code => 422,
                                               msg => "Identical 'start' timestamps not allowed"}, 
                                
                                
                                
                                
                                );
    
    foreach my $test (@malformed_profilemappings) {
        foreach my $mappings (@{$test->{mappings}}) {
            $req->content(JSON::to_json(
                [ { op => 'replace', path => '/billing_profiles', value => $mappings } ]
            ));
            $res = $ua->request($req);
            is($res->code, $test->{code}, "multi-bill-prof PATCH: check " . $test->{msg});
        }
    }
    
    $req->content(JSON::to_json(
                [ { op => 'replace', path => '/billing_profile_id', value => $billing_profile_id } ]
            ));
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: patch test contract with new billing profile");
    my $patched_contract = JSON::from_json($res->decoded_content);
    
    #$req = HTTP::Request->new('GET', $contracturi);
    #$res = $ua->request($req);
    #is($res->code, 200, "multi-bill-prof: fetch patched contract");
    #my $patched_contract = JSON::from_json($res->decoded_content);
    
    ok(exists $patched_contract->{billing_profile_id}, "multi-bill-prof: check existence of billing_profile_id");
    is($patched_contract->{billing_profile_id}, $billing_profile_id,"multi-bill-prof: check if billing_profile_id is correct");
    ok(exists $patched_contract->{billing_profiles}, "multi-bill-prof: check existence of billing_profiles");
    is(scalar @{$patched_contract->{billing_profiles}},(scalar @{$data->{billing_profiles}}) + 1,"multi-bill-prof: check if the history of billing mappings shows the correct number of entries");
    
    $req = HTTP::Request->new('PATCH', $contracturi);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    
    $data->{billing_profiles} = [ 
                                 { profile_id => $billing_profile_id,
                               start => $dtf->format_datetime($t1),
                               stop => $dtf->format_datetime($t2),},
                                 { profile_id => $billing_profile_id,
                               start => $dtf->format_datetime($t2),
                               stop => $dtf->format_datetime($t3),},
                                 { profile_id => $second_billing_profile_id,
                                 start => $dtf->format_datetime($t3),
                               stop => undef,}];
    my @expected_mappings = (@{_strip_future_mappings($patched_contract->{billing_profiles})},@{$data->{billing_profiles}});
    $req->content(JSON::to_json(
                [ { op => 'replace', path => '/billing_profiles', value => $data->{billing_profiles} } ]
            ));
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: patch test contract");
    $patched_contract = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('GET', $contracturi);
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: fetch patched contract");
    #$patched_contract = JSON::from_json($res->decoded_content);
    is_deeply(JSON::from_json($res->decoded_content),$patched_contract,"multi-bill-prof: check patch return value is up-to-date");    

    ok(exists $patched_contract->{billing_profile_id}, "multi-bill-prof: check existence of billing_profile_id");
    is($patched_contract->{billing_profile_id}, $billing_profile_id,"multi-bill-prof: check if billing_profile_id is correct");    
    ok(exists $contract->{billing_profiles}, "multi-bill-prof: check existence of billing_profiles");
    is_deeply($patched_contract->{billing_profiles},\@expected_mappings,"multi-bill-prof: check patched billing mappings deeply");    

    $req = HTTP::Request->new('PUT', $contracturi);
    $req->header('Prefer' => "return=representation");    
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json($data));
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: put test contract");
    my $updated_contract = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('GET', $contracturi);
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: fetch updated contract");
    #my $updated_contract = JSON::from_json($res->decoded_content);
    is_deeply(JSON::from_json($res->decoded_content),$updated_contract,"multi-bill-prof: check put return value is up-to-date");   

    ok(exists $updated_contract->{billing_profile_id}, "multi-bill-prof: check existence of billing_profile_id");
    is($updated_contract->{billing_profile_id}, $billing_profile_id,"multi-bill-prof: check if billing_profile_id is correct");    
    ok(exists $updated_contract->{billing_profiles}, "multi-bill-prof: check existence of billing_profiles");
    is_deeply($updated_contract->{billing_profiles},\@expected_mappings,"multi-bill-prof: check patched billing mappings deeply");
    
    #$req = HTTP::Request->new('DELETE', $billingnetwork_uri);
    #$res = $ua->request($req);
    #is($res->code, 204, "multi-bill-prof: delete test billingnetwork");
    
    #pop(@expected_mappings);
    
    #$req = HTTP::Request->new('GET', $contracturi);
    #$res = $ua->request($req);
    #is($res->code, 200, "multi-bill-prof: fetch contract");
    ##$patched_contract = JSON::from_json($res->decoded_content);
    #is_deeply(JSON::from_json($res->decoded_content)->{billing_profiles},\@expected_mappings,"multi-bill-prof: check billing network cascade delete ");  
}

sub _strip_future_mappings {
    my ($mappings) = @_;
    my @stripped_mappings = ();
    my $now = DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local')
    );
    foreach my $m (@$mappings) {
        if (!defined $m->{start}) {
            push(@stripped_mappings,$m);
            next;
        }
        my $s = $m->{start};
        $s =~ s/^(\d{4}\-\d{2}\-\d{2})\s+(\d.+)$/$1T$2/;
        my $start = DateTime::Format::ISO8601->parse_datetime($s);
        $start->set_time_zone( DateTime::TimeZone->new(name => 'local') );
        push(@stripped_mappings,$m) if ($start <= $now);
    }
    return \@stripped_mappings;
}


done_testing;

# vim: set tabstop=4 expandtab:
