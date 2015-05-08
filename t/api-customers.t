# TODO: try to set reseller_id of contact of a system customer, which should fail

use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

use DateTime qw();
use DateTime::Format::Strptime qw();
use DateTime::Format::ISO8601 qw();

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

# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/customers/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-customers", "check Accept-Post header in options response");
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

# fetch a system contact for later tests
$req = HTTP::Request->new('GET', $uri.'/api/systemcontacts/?page=1&rows=1');
$res = $ua->request($req);
is($res->code, 200, "fetch system contacts");
my $sysct = JSON::from_json($res->decoded_content);
my $system_contact_id = $sysct->{_embedded}->{'ngcp:systemcontacts'}->{id};

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

# collection test
my $firstcustomer = undef;
my @allcustomers = ();
{

    # create 6 new customers
    my %customers = ();
    for(my $i = 1; $i <= 6; ++$i) {
        $req = HTTP::Request->new('POST', $uri.'/api/customers/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            status => "active",
            contact_id => $custcontact->{id},
            type => "sipaccount",
            billing_profile_id => $billing_profile_id,
            max_subscribers => undef,
            external_id => undef,
        }));
        $res = $ua->request($req);
        is($res->code, 201, "create test customer $i");
        $customers{$res->header('Location') // ''} = 1;
        push @allcustomers, $res->header('Location');
        $firstcustomer = $res->header('Location') unless $firstcustomer;
    }

    # try to create invalid customer with wrong type
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $custcontact->{id},
        billing_profile_id => $billing_profile_id,
        max_subscribers => undef,
        external_id => undef,
        type => "invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create customer with invalid type");
    my $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    #ok($err->{message} =~ /Mandatory 'type' parameter is empty or invalid/, "check error message in body");
    ok($err->{message} =~ /is not a valid value/, "check error message in body");

    # try to create invalid customer with wrong billing profile
    $req->content(JSON::to_json({
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        max_subscribers => undef,
        external_id => undef,
        billing_profile_id => 999999,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create customer with invalid billing profile");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'billing_profile_id'/, "check error message in body");

    # try to create invalid customer with systemcontact
    $req->content(JSON::to_json({
        status => "active",
        type => "sipaccount",
        billing_profile_id => $billing_profile_id,
        max_subscribers => undef,
        external_id => undef,
        contact_id => $system_contact_id,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create customer with invalid contact");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /The contact_id is not a valid ngcp:customercontacts item/, "check error message in body");
    
    # try to create invalid customer without contact
    $req->content(JSON::to_json({
        status => "active",
        type => "sipaccount",
        billing_profile_id => $billing_profile_id,
        max_subscribers => undef,
        external_id => undef,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create customer without contact");

    # try to create invalid customer with invalid status
    $req->content(JSON::to_json({
        type => "sipaccount",
        billing_profile_id => $billing_profile_id,
        contact_id => $custcontact->{id},
        max_subscribers => undef,
        external_id => undef,
        status => "invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create customer with invalid status");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='status'/, "check error message in body");

    # try to create invalid customer with invalid max_subscribers
    $req->content(JSON::to_json({
        type => "sipaccount",
        billing_profile_id => $billing_profile_id,
        contact_id => $custcontact->{id},
        max_subscribers => "abc",
        external_id => undef,
        status => "active",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create customer with invalid max_subscribers");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='max_subscribers'/, "check error message in body");

    # iterate over customers collection to check next/prev links and status
    my $nexturi = $uri.'/api/customers/?page=1&rows=5&status=active';
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
        ok((ref $collection->{_links}->{'ngcp:customers'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:customers'} eq "HASH"), "check if 'ngcp:customers' is array/hash-ref");

        # remove any contact we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:customers'} eq "HASH") {
            ok($collection->{_embedded}->{'ngcp:customers'}->{type} eq "sipaccount" || $collection->{_embedded}->{'ngcp:customers'}->{type} eq "pbxaccount", "check for correct customer contract type");
            ok($collection->{_embedded}->{'ngcp:customers'}->{status} ne "terminated", "check if we don't have terminated customers in response");
            ok(exists $collection->{_embedded}->{'ngcp:customers'}->{_links}->{'ngcp:customercontacts'}, "check presence of ngcp:customercontacts relation");
            ok(exists $collection->{_embedded}->{'ngcp:customers'}->{_links}->{'ngcp:billingprofiles'}, "check presence of ngcp:billingprofiles relation");
            ok(exists $collection->{_embedded}->{'ngcp:customers'}->{_links}->{'ngcp:customerbalances'}, "check presence of ngcp:customerbalances relation");
            delete $customers{$collection->{_links}->{'ngcp:customers'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:customers'} }) {
                delete $customers{$c->{href}};
            }
            foreach my $c(@{ $collection->{_embedded}->{'ngcp:customers'} }) {
                ok($c->{type} eq "sipaccount" || $c->{type} eq "pbxaccount", "check for correct customer contract type");
                ok($c->{status} ne "terminated", "check if we don't have terminated customers in response");
                ok(exists $c->{_links}->{'ngcp:customercontacts'}, "check presence of ngcp:customercontacts relation");
                ok(exists $c->{_links}->{'ngcp:billingprofiles'}, "check presence of ngcp:billingprofiles relation");
                ok(exists $c->{_links}->{'ngcp:customerbalances'}, "check presence of ngcp:contractbalances relation");

                delete $customers{$c->{_links}->{self}->{href}};
            }
        }
             
    } while($nexturi);

    is(scalar(keys %customers), 0, "check if all test customers have been found");
}

# test contacts item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstcustomer);
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

    $req = HTTP::Request->new('GET', $uri.'/'.$firstcustomer);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one customer item");
    my $customer = JSON::from_json($res->decoded_content);
    ok(exists $customer->{status}, "check existence of status");
    ok(exists $customer->{type}, "check existence of type");
    ok(exists $customer->{billing_profile_id} && $customer->{billing_profile_id}->is_int, "check existence of billing_profile_id");
    ok(exists $customer->{contact_id} && $customer->{contact_id}->is_int, "check existence of contact_id");
    ok(exists $customer->{id} && $customer->{id}->is_int, "check existence of id");
    ok(exists $customer->{max_subscribers}, "check existence of max_subscribers");
    ok(!exists $customer->{product_id}, "check absence of product_id");
    ok(exists $customer->{all_billing_profiles}, "check existence of all_billing_profiles");
    is_deeply($customer->{all_billing_profiles},[ { profile_id => $billing_profile_id, start => undef, stop => undef, network_id => undef} ],"check all_billing_profiles deeply");
    
    # PUT same result again
    my $old_customer = { %$customer };
    delete $customer->{_links};
    delete $customer->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstcustomer);
    
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
    my $reput_customer = { %$old_customer };
    delete $reput_customer->{billing_profiles};
    $req->content(JSON::to_json($reput_customer));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_customer = JSON::from_json($res->decoded_content);
    is_deeply($old_customer, $new_customer, "check put if unmodified put returns the same");

    # check if we have the proper links
    ok(exists $new_customer->{_links}->{'ngcp:customercontacts'}, "check put presence of ngcp:customercontacts relation");
    ok(exists $new_customer->{_links}->{'ngcp:billingprofiles'}, "check put presence of ngcp:billingprofiles relation");
    ok(exists $new_customer->{_links}->{'ngcp:customerbalances'}, "check put presence of ngcp:contractbalances relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstcustomer);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'pending' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched customer item");
    my $mod_contact = JSON::from_json($res->decoded_content);
    is($mod_contact->{status}, "pending", "check patched replace op");
    is($mod_contact->{_links}->{self}->{href}, $firstcustomer, "check patched self link");
    is($mod_contact->{_links}->{collection}->{href}, '/api/customers/', "check patched collection link");
    
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
        [ { op => 'replace', path => '/contact_id', value => $system_contact_id } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched system contact_id");

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

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/max_subscribers', value => "abc" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid max_subscribers");
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
    
    $req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test billing network " . $t,
        description  => "test billing network description " . $t,
        reseller_id => $reseller_id,
        blocks => [{ip=>'10.0.4.7',mask=>26}, #0..63
                      {ip=>'10.0.4.99',mask=>26}, #64..127
                      {ip=>'10.0.5.9',mask=>24},
                        {ip=>'10.0.6.9',mask=>24},],
    }));
    $res = $ua->request($req);
    is($res->code, 201, "multi-bill-prof: create test billingnetwork");
    # TODO: get id from body once the API returns it
    #my $billingnetwork_uri = $uri.'/'.$res->header('Location');
    my $billing_network_id = $res->header('Location');
    $billing_network_id =~ s/^.+\/(\d+)$/$1/;
    
    my $dtf = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    ); #DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );
    my $now = DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local')
    );
    my $t1 = $now->clone->add(days => 1);
    my $t2 = $now->clone->add(days => 2);
    my $t3 = $now->clone->add(days => 3);

    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');

    my $data = {
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        max_subscribers => undef,
        external_id => undef,
        billing_profile_definition => 'profiles',
    };
    
    my @malformed_profilemappings = ( { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($now),
                                                                stop => $dtf->format_datetime($now),} ]],
                                               code => 422,
                                               msg => "'start' timestamp is not in future"},
                                        { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($t1),
                                                                stop => $dtf->format_datetime($t1),} ]],
                                               code => 422,
                                               msg => "'start' timestamp has to be before 'stop' timestamp"},                                       
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
                                 #{ mappings =>[[ { profile_id => $billing_profile_id,
                                 #                               start => undef,
                                 #                               stop => undef,},
                                 #               { profile_id => $billing_profile_id,
                                 #                               start => undef,
                                 #                               stop => undef,}]],
                                 #              code => 422,
                                 #              msg => "Only a single interval without 'start' and 'stop' timestamps is allowed"},                                   
                                 #{ mappings =>[[ { profile_id => $billing_profile_id,
                                 #                               start => undef,
                                 #                               stop => undef,},
                                 #               { profile_id => $billing_profile_id,
                                 #                               start => $dtf->format_datetime($t1),
                                 #                               stop => $dtf->format_datetime($t2),},
                                 #               { profile_id => $billing_profile_id,
                                 #                               start => $dtf->format_datetime($t1),
                                 #                               stop => undef,}]],
                                 #              code => 422,
                                 #              msg => "Identical 'start' timestamps not allowed"}, 
                                
                                
                                
                                
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
                               stop => undef,
                               network_id => undef },
                                 { profile_id => $billing_profile_id,
                               start => $dtf->format_datetime($t1),
                               stop => $dtf->format_datetime($t2),
                               network_id => undef },
                                 { profile_id => $billing_profile_id,
                               start => $dtf->format_datetime($t2),
                               stop => $dtf->format_datetime($t3),
                               network_id => undef }];
    $req->content(JSON::to_json($data));
    $res = $ua->request($req);
    is($res->code, 201, "multi-bill-prof: create test customer");
    my $customeruri = $uri.'/'.$res->header('Location');
    
    $req = HTTP::Request->new('GET', $customeruri);
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: fetch customer");
    my $customer = JSON::from_json($res->decoded_content);

    ok(exists $customer->{billing_profile_id}, "multi-bill-prof: check existence of billing_profile_id");
    is($customer->{billing_profile_id}, $second_billing_profile_id,"multi-bill-prof: check if billing_profile_id is correct");    
    ok(exists $customer->{billing_profiles}, "multi-bill-prof: check existence of billing_profiles");
    ok(exists $customer->{all_billing_profiles}, "multi-bill-prof: check existence of all_billing_profiles");
    is_deeply($customer->{all_billing_profiles},$data->{billing_profiles},"multi-bill-prof: check billing mappings deeply");
    
    
    $req = HTTP::Request->new('PATCH', $customeruri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');

    @malformed_profilemappings = ( { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($now),
                                                                stop => $dtf->format_datetime($now),} ]],
                                               code => 422,
                                               msg => "'start' timestamp is not in future"},
                                        { mappings =>[[ { profile_id => $billing_profile_id,
                                                                start => $dtf->format_datetime($t1),
                                                                stop => $dtf->format_datetime($t1),} ]],
                                               code => 422,
                                               msg => "'start' timestamp has to be before 'stop' timestamp"},                                    
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
                                 #{ mappings =>[[ { profile_id => $billing_profile_id,
                                 #                               start => undef,
                                 #                               stop => undef,},
                                 #               { profile_id => $billing_profile_id,
                                 #                               start => $dtf->format_datetime($t1),
                                 #                               stop => $dtf->format_datetime($t2),},
                                 #               { profile_id => $billing_profile_id,
                                 #                               start => $dtf->format_datetime($t1),
                                 #                               stop => undef,}]],
                                 #              code => 422,
                                 #              msg => "Identical 'start' timestamps not allowed"}, 
                                
                                
                                
                                
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
    is($res->code, 200, "multi-bill-prof: patch test customer with new billing profile");
    my $patched_customer = JSON::from_json($res->decoded_content);
    
    #$req = HTTP::Request->new('GET', $customeruri);
    #$res = $ua->request($req);
    #is($res->code, 200, "multi-bill-prof: fetch patched customer");
    #my $patched_customer = JSON::from_json($res->decoded_content);
    
    ok(exists $patched_customer->{billing_profile_id}, "multi-bill-prof: check existence of billing_profile_id");
    is($patched_customer->{billing_profile_id}, $billing_profile_id,"multi-bill-prof: check if billing_profile_id is correct");
    ok(exists $patched_customer->{billing_profiles}, "multi-bill-prof: check existence of billing_profiles");
    ok(exists $patched_customer->{all_billing_profiles}, "multi-bill-prof: check existence of all_billing_profiles");
    is(scalar @{$patched_customer->{all_billing_profiles}},(scalar @{$data->{billing_profiles}}) + 1,"multi-bill-prof: check if the history of billing mappings shows the correct number of entries");
    
    $req = HTTP::Request->new('PATCH', $customeruri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    
    $data->{billing_profiles} = [ 
                                 { profile_id => $billing_profile_id,
                               start => $dtf->format_datetime($t1),
                               stop => $dtf->format_datetime($t2),
                               network_id => undef},
                                 { profile_id => $billing_profile_id,
                               start => $dtf->format_datetime($t2),
                               stop => $dtf->format_datetime($t3),
                               network_id => undef},
                                 { profile_id => $second_billing_profile_id,
                                 start => $dtf->format_datetime($t3),
                               stop => undef,
                               network_id => $billing_network_id}];
    my @expected_mappings = (@{_strip_future_mappings($patched_customer->{billing_profiles})},@{$data->{billing_profiles}});
    $req->content(JSON::to_json(
                [ { op => 'replace', path => '/billing_profiles', value => $data->{billing_profiles} } ]
            ));
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: patch test customer");
    $patched_customer = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('GET', $customeruri);
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: fetch patched customer");
    #$patched_customer = JSON::from_json($res->decoded_content);
    is_deeply(JSON::from_json($res->decoded_content),$patched_customer,"multi-bill-prof: check patch return value is up-to-date");    

    ok(exists $patched_customer->{billing_profile_id}, "multi-bill-prof: check existence of billing_profile_id");
    is($patched_customer->{billing_profile_id}, $billing_profile_id,"multi-bill-prof: check if billing_profile_id is correct");    
    ok(exists $customer->{billing_profiles}, "multi-bill-prof: check existence of billing_profiles");
    #ok(exists $customer->{all_billing_profiles}, "multi-bill-prof: check existence of all_billing_profiles");
    is_deeply($patched_customer->{billing_profiles},\@expected_mappings,"multi-bill-prof: check patched billing mappings deeply");    

    $req = HTTP::Request->new('PUT', $customeruri);
    $req->header('Prefer' => "return=representation");    
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json($data));
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: put test customer");
    my $updated_customer = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('GET', $customeruri);
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: fetch updated customer");
    #my $updated_customer = JSON::from_json($res->decoded_content);
    is_deeply(JSON::from_json($res->decoded_content),$updated_customer,"multi-bill-prof: check put return value is up-to-date");   

    ok(exists $updated_customer->{billing_profile_id}, "multi-bill-prof: check existence of billing_profile_id");
    is($updated_customer->{billing_profile_id}, $billing_profile_id,"multi-bill-prof: check if billing_profile_id is correct");    
    ok(exists $updated_customer->{billing_profiles}, "multi-bill-prof: check existence of billing_profiles");
    #ok(exists $updated_customer->{all_billing_profiles}, "multi-bill-prof: check existence of all_billing_profiles");
    is_deeply($updated_customer->{billing_profiles},\@expected_mappings,"multi-bill-prof: check patched billing mappings deeply");
    
    #$req = HTTP::Request->new('DELETE', $billingnetwork_uri);
    #$res = $ua->request($req);
    #is($res->code, 204, "multi-bill-prof: delete test billingnetwork");
    #
    #pop(@expected_mappings);
    #
    #$req = HTTP::Request->new('GET', $customeruri);
    #$res = $ua->request($req);
    #is($res->code, 200, "multi-bill-prof: fetch customer");
    ##$patched_customer = JSON::from_json($res->decoded_content);
    #is_deeply(JSON::from_json($res->decoded_content)->{billing_profiles},\@expected_mappings,"multi-bill-prof: check billing network cascade delete ");
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingprofiles/'.$second_billing_profile_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "multi-bill-prof: try to terminate second billing profile");
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingnetworks/'.$billing_network_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "multi-bill-prof: try to terminate billing network");
    
    $req = HTTP::Request->new('PATCH', $customeruri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: terminate customer");
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingprofiles/'.$second_billing_profile_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: terminate second billing profile");
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingnetworks/'.$billing_network_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "multi-bill-prof: terminate billing network");
    
}

{
    
    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "THIRD test profile $t",
        handle  => "third_testprofile$t",
        reseller_id => $reseller_id,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "prof-package: create another test billing profile");
    # TODO: get id from body once the API returns it
    my $third_billing_profile_id = $res->header('Location');
    $third_billing_profile_id =~ s/^.+\/(\d+)$/$1/;
    
    $req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "another test billing network " . $t,
        description  => "another test billing network description " . $t,
        reseller_id => $reseller_id,
        blocks => [{ip=>'10.0.4.7',mask=>26}, #0..63
                      {ip=>'10.0.4.99',mask=>26}, #64..127
                      {ip=>'10.0.5.9',mask=>24},
                        {ip=>'10.0.6.9',mask=>24},],
    }));
    $res = $ua->request($req);
    is($res->code, 201, "prof-package: create test billingnetwork");
    # TODO: get id from body once the API returns it
    my $second_billingnetwork_uri = $uri.'/'.$res->header('Location');
    my $second_billing_network_id = $res->header('Location');
    $second_billing_network_id =~ s/^.+\/(\d+)$/$1/;
    
    my $initial_profiles = [ { profile_id => $billing_profile_id, } ,
                             { profile_id => $third_billing_profile_id, network_id => $second_billing_network_id } ];    
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({ name => 'test profile package '.($t-1),
                                  description => 'test profile package '.($t-1),
                                  initial_profiles => $initial_profiles},
                                ));
    $res = $ua->request($req);
    is($res->code, 201, "prof-package: create test profile package");
    # TODO: get id from body once the API returns it
    my $profile_package_uri = $uri.'/'.$res->header('Location');
    my $profile_package_id = $res->header('Location');
    $profile_package_id =~ s/^.+\/(\d+)$/$1/;
    
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({ name => 'test profile package '.$t,
                                  description => 'test profile package '.$t,
                                  initial_profiles => $initial_profiles},
                                ));
    $res = $ua->request($req);
    is($res->code, 201, "prof-package: create test profile package");
    # TODO: get id from body once the API returns it
    my $second_profile_package_uri = $uri.'/'.$res->header('Location');
    my $second_profile_package_id = $res->header('Location');
    $second_profile_package_id =~ s/^.+\/(\d+)$/$1/;        
    
    $req = HTTP::Request->new('POST', $uri.'/api/customers/');
    $req->header('Content-Type' => 'application/json');    
    my $data = {
        status => "active",
        contact_id => $custcontact->{id},
        type => "sipaccount",
        max_subscribers => undef,
        external_id => undef,
        profile_package_id => $profile_package_id,
        billing_profile_definition => "package",
    };
    $req->content(JSON::to_json($data));
    $res = $ua->request($req);
    is($res->code, 201, "prof-package: create test customer");
    my $customeruri = $uri.'/'.$res->header('Location');    
    $req = HTTP::Request->new('GET', $customeruri);
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: fetch customer");
    my $customer = JSON::from_json($res->decoded_content);
    
    ok(exists $customer->{billing_profile_id}, "prof-package: check existence of billing_profile_id");
    is($customer->{billing_profile_id}, $third_billing_profile_id,"prof-package: check if billing_profile_id is correct");
    ok(exists $customer->{profile_package_id}, "prof-package: check existence of profile_package_id");
    is($customer->{profile_package_id}, $profile_package_id,"prof-package: check if profile_package_id is correct");        
    my @profile_networks = @$initial_profiles;
    _check_mappings(\@profile_networks,$customer);
    #ok(exists $customer->{all_billing_profiles}, "prof-package: check existence of all_billing_profiles");
    #is(scalar @{ $customer->{all_billing_profiles} }, 2, "prof-package: check if all_billing_profiles shows the correct number of profile mappings");
    #is_deeply($customer->{all_billing_profiles},\@expected_mappings,"multi-bill-prof: check patched billing mappings deeply");
    
    $req = HTTP::Request->new('PATCH', $customeruri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    

    my $dtf = DateTime::Format::Strptime->new(
        pattern => '%F %T', 
    ); #DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );
    my $now = DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local')
    );
    my $t1 = $now->clone->add(days => 1);
    my $t2 = $now->clone->add(days => 2);
    my $t3 = $now->clone->add(days => 3);
    
    $data->{billing_profiles} = [ { profile_id => $billing_profile_id,
                                    start => $dtf->format_datetime($t1),
                                    stop => $dtf->format_datetime($t2) } ,
                                  { profile_id => $third_billing_profile_id,
                                    network_id => $second_billing_network_id,
                                    start => $dtf->format_datetime($t2),
                                    stop => $dtf->format_datetime($t3) } ];    
    $req->content(JSON::to_json(
                [ { op => 'replace', path => '/billing_profiles', value => $data->{billing_profiles} } ]
            ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: patch test customer");
    $customer = JSON::from_json($res->decoded_content);
    
    ok(exists $customer->{billing_profile_id}, "prof-package: check existence of billing_profile_id");
    is($customer->{billing_profile_id}, $third_billing_profile_id,"prof-package: check if billing_profile_id is unchanged");
    ok(exists $customer->{profile_package_id}, "prof-package: check existence of profile_package_id");
    is($customer->{profile_package_id}, $profile_package_id,"prof-package: check if profile_package_id is unchanged");        
    push(@profile_networks,@{$data->{billing_profiles}});
    _check_mappings(\@profile_networks,$customer);   
    



    $data->{billing_profile_id} = $billing_profile_id;
    $req->content(JSON::to_json(
                [ { op => 'replace', path => '/billing_profile_id', value => $data->{billing_profile_id} } ]
            ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: patch test customer");
    $customer = JSON::from_json($res->decoded_content);
    
    ok(exists $customer->{billing_profile_id}, "prof-package: check existence of billing_profile_id");
    is($customer->{billing_profile_id}, $data->{billing_profile_id},"prof-package: check if billing_profile_id is updated");
    ok(exists $customer->{profile_package_id}, "prof-package: check existence of profile_package_id");
    is($customer->{profile_package_id}, $profile_package_id,"prof-package: check if profile_package_id is unchanged");        
    @profile_networks = @$initial_profiles;
    push(@profile_networks,{ profile_id => $data->{billing_profile_id} });
    push(@profile_networks,@{$data->{billing_profiles}});
    _check_mappings(\@profile_networks,$customer);
    
    
    
    $data->{profile_package_id} = $profile_package_id;
    $req->content(JSON::to_json(
                [ { op => 'replace', path => '/profile_package_id', value => $data->{profile_package_id} } ]
            ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: patch test customer");
    $customer = JSON::from_json($res->decoded_content);
    
    ok(exists $customer->{billing_profile_id}, "prof-package: check existence of billing_profile_id");
    is($customer->{billing_profile_id}, $data->{billing_profile_id},"prof-package: check if billing_profile_id is unchanged");
    ok(exists $customer->{profile_package_id}, "prof-package: check existence of profile_package_id");
    is($customer->{profile_package_id}, $data->{profile_package_id},"prof-package: check if profile_package_id is unchanged");        
    _check_mappings(\@profile_networks,$customer);      

    $data->{profile_package_id} = $second_profile_package_id;
    $req->content(JSON::to_json(
                [ { op => 'replace', path => '/profile_package_id', value => $data->{profile_package_id} } ]
            ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: patch test customer");
    $customer = JSON::from_json($res->decoded_content);
    
    ok(exists $customer->{billing_profile_id}, "prof-package: check existence of billing_profile_id");
    is($customer->{billing_profile_id}, $third_billing_profile_id,"prof-package: check if billing_profile_id is updated");
    ok(exists $customer->{profile_package_id}, "prof-package: check existence of profile_package_id");
    is($customer->{profile_package_id}, $data->{profile_package_id},"prof-package: check if profile_package_id is updated");
    @profile_networks = @$initial_profiles;
    push(@profile_networks,{ profile_id => $data->{billing_profile_id} });
    push(@profile_networks,@$initial_profiles);
    push(@profile_networks,@{$data->{billing_profiles}});    
    _check_mappings(\@profile_networks,$customer);    
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingprofiles/'.$third_billing_profile_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "prof-package: try to terminate third billing profile");
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingnetworks/'.$second_billing_network_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "prof-package: try to terminate second billing network");
    
    $req = HTTP::Request->new('PATCH', $customeruri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: terminate customer");
    
    $req = HTTP::Request->new('PATCH', $profile_package_uri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: terminate profile package");
    
    $req = HTTP::Request->new('PATCH', $second_profile_package_uri);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: terminate second profile package");      
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingprofiles/'.$third_billing_profile_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: terminate third billing profile");
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingnetworks/'.$second_billing_network_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "prof-package: terminate second billing network");
    
}

# terminate
{
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingprofiles/'.$billing_profile_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "try to terminate billing profile");
    
    # check if deletion of contact fails before terminating the customers
    $req = HTTP::Request->new('DELETE', $uri.'/'.$custcontact->{_links}->{self}->{href});
    $res = $ua->request($req);
    is($res->code, 423, "check locked status for deleting used contact");

    my $pc;
    foreach my $customer(@allcustomers) {
        $req = HTTP::Request->new('PATCH', $uri.'/'.$customer);
        $req->header('Content-Type' => 'application/json-patch+json');
        $req->header('Prefer' => 'return=representation');
        $req->content(JSON::to_json([
            { "op" => "replace", "path" => "/status", "value" => "terminated" }
        ]));
        $res = $ua->request($req);
        is($res->code, 200, "check termination of customer");
        $pc = JSON::from_json($res->decoded_content);
        is($pc->{status}, "terminated", "check termination status of customer");
    }
    
    $req = HTTP::Request->new('PATCH', $uri.'/api/billingprofiles/'.$billing_profile_id);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "terminate billing profile");
}

sub _check_mappings {
    my ($profile_networks,$customer) = @_;
    my $now = DateTime->now(
        time_zone => DateTime::TimeZone->new(name => 'local')
    );
    my $start_found = 0;
    ok(exists $customer->{all_billing_profiles}, "prof-package: check existence of all_billing_profiles");
    is(scalar @{$customer->{all_billing_profiles}}, scalar @$profile_networks, "prof-package: check expected number of " . scalar @$profile_networks . " profile mappings");
    for (my $i = 0; $i < scalar @$profile_networks; $i++) {
        my $profile_network = $profile_networks->[$i];
        my $mapping = $customer->{all_billing_profiles}->[$i];
        is($mapping->{profile_id}, $profile_network->{profile_id}, "prof-package: check profile mapping ".($i+1)." billing profile");
        if (defined $profile_network->{network_id}) {
            is($mapping->{network_id}, $profile_network->{network_id}, "prof-package: check profile mapping ".($i+1)." billing network");
        } else {
            ok(!defined $mapping->{network_id}, "prof-package: check profile mapping ".($i+1)." billing network (null)");
        }
        if ($i == 0) {
            ok(!defined $mapping->{start} && !defined $mapping->{stop}, "prof-package: check if first profile mapping is an open interval");
            ok(!defined $mapping->{network_id}, "prof-package: check if first profile mapping has no billing network");
        } else {
            my $s = $mapping->{start};
            if (defined $s) {
                #$s =~ s/^(\d{4}\-\d{2}\-\d{2})\s+(\d.+)$/$1T$2/;
                #my $start = DateTime::Format::ISO8601->parse_datetime($s);
                #$start->set_time_zone( DateTime::TimeZone->new(name => 'local') );
                #ok($start < $now, "prof-package: check profile mapping ".($i+1)." start is past");
                #ok(!defined $mapping->{stop}, "prof-package: check if profile mapping ".($i+1)." is a right-open interval");
                $start_found = 1;
            } else {
                ok(!$start_found, "prof-package: check if profile mapping ".($i+1)." is not an open interval");
                ok(!defined $mapping->{stop}, "prof-package: check if profile mapping ".($i+1)." is an open interval");
            }
            if (defined $profile_network->{start}) {
                is($mapping->{start}, $profile_network->{start}, "prof-package: check profile mapping ".($i+1)." start");
            }
            if (defined $profile_network->{stop}) {
                is($mapping->{stop}, $profile_network->{stop}, "prof-package: check profile mapping ".($i+1)." stop");
            }
        }
    }
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
