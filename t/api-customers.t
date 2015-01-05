# TODO: try to set reseller_id of contact of a system customer, which should fail

use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my $valid_ssl_client_cert = $ENV{API_SSL_CLIENT_CERT} || 
    "/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate.pem";
my $valid_ssl_client_key = $ENV{API_SSL_CLIENT_KEY} ||
    $valid_ssl_client_cert;
my $ssl_ca_cert = $ENV{API_SSL_CA_CERT} || "/etc/ngcp-panel/api_ssl/api_ca.crt";

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
    SSL_cert_file => $valid_ssl_client_cert,
    SSL_key_file  => $valid_ssl_client_key,
    SSL_ca_file   => $ssl_ca_cert,
);

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

# collection test
my $firstcustomer = undef;
my $custcontact = undef;
my @allcustomers = ();
{
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
    is($res->code, 200, "fetch system contact");
    $custcontact = JSON::from_json($res->decoded_content);

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
    ok($err->{message} =~ /Mandatory 'type' parameter is empty or invalid/, "check error message in body");

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
    $req->content(JSON::to_json($customer));
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

# terminate
{
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
}

done_testing;

# vim: set tabstop=4 expandtab:
