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
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/resellers/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    ok($res->header('Accept-Post') eq "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-resellers", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

# collection test
my $syscontact;
my @allcontracts = ();
my @allcontractids = ();
my $firstcontract_id = undef;
my $secondcontract_id = undef;
my $firstreseller = undef;
my $billing_profile_id = 1;
my $t = time;
my @allresellers = ();
{
    # first, we need a contact
    $req = HTTP::Request->new('POST', $uri.'/api/systemcontacts/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        email => "reseller$t\@reseller.invalid",
        firstname => "api test first",
        lastname => "api test last",
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create system contact");
    $syscontact = $res->header('Location');
    # TODO: should be returned in post result
    my $contact_id = $syscontact;
    $contact_id =~ s/^.+\/(\d+)$/$1/;

    # next, we need reseller contracts
    $req = HTTP::Request->new('POST', $uri.'/api/contracts/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        contact_id => $contact_id,
        status => "active",
        type => "reseller",
        billing_profile_id => $billing_profile_id,
    }));
    for(my $i = 1; $i <= 7; ++$i) { # create one more for later tests
        $res = $ua->request($req);
        is($res->code, 201, "create reseller contract");
        my $syscontract = $res->header('Location');
        # TODO: should be returned in post result
        my $contract_id = $syscontract;
        $contract_id =~ s/^.+\/(\d+)$/$1/;
        push @allcontracts, $syscontract;
        push @allcontractids, $contract_id;
        $secondcontract_id = $contract_id if($firstcontract_id && !$secondcontract_id);
        $firstcontract_id = $contract_id unless $firstcontract_id;
    }
    
    # create 6 new resellers
    my %resellers = ();
    for(my $i = 1; $i <= 6; ++$i) {
        my $contract_id = shift @allcontractids;
        $req = HTTP::Request->new('POST', $uri.'/api/resellers/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            contract_id => $contract_id,
            name => "test reseller $t $i",
            status => "active",
        }));
        $res = $ua->request($req);
        is($res->code, 201, "create test reseller $i");
        $resellers{$res->header('Location')} = 1;
        push @allresellers, $res->header('Location');
        $firstreseller = $res->header('Location') unless $firstreseller;
    }

    my $err;
    my $new_contract_id = shift @allcontractids;

    # try to create reseller without contract_id
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        name => "test reseller $t 999",
        status => "active",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create reseller without contract_id");
    $err = JSON::from_json($res->decoded_content);
    ok($err->{code} eq "422", "check error code in body");
    ok($err->{message} =~ /field='contract_id'/, "check error message in body");

    # try to create reseller with empty contract_id
    $req->content(JSON::to_json({
        contract_id => undef,    
        name => "test reseller $t 999",
        status => "active",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create reseller with empty contract_id");
    $err = JSON::from_json($res->decoded_content);
    ok($err->{code} eq "422", "check error code in body");
    ok($err->{message} =~ /field='contract_id'/, "check error message in body");

    # try to create reseller with existing contract_id
    $req->content(JSON::to_json({
        contract_id => $firstcontract_id,
        name => "test reseller $t 999",
        status => "active",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create reseller with existing contract_id");
    $err = JSON::from_json($res->decoded_content);
    ok($err->{code} eq "422", "check error code in body");
    ok($err->{message} =~ /reseller with this contract already exists/, "check error message in body");

    # try to create reseller with existing name
    $req->content(JSON::to_json({
        contract_id => $new_contract_id,
        name => "test reseller $t 1",
        status => "active",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create reseller with existing name");
    $err = JSON::from_json($res->decoded_content);
    ok($err->{code} eq "422", "check error code in body");
    ok($err->{message} =~ /reseller with this name already exists/, "check error message in body");

    # try to create reseller with missing name
    $req->content(JSON::to_json({
        contract_id => $new_contract_id,
        status => "active",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create reseller with missing name");
    $err = JSON::from_json($res->decoded_content);
    ok($err->{code} eq "422", "check error code in body");
    ok($err->{message} =~ /field='name'/, "check error message in body");

    # try to create reseller with missing status
    $req->content(JSON::to_json({
        contract_id => $new_contract_id,
        name => "test reseller $t 999",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create reseller with invalid status");
    $err = JSON::from_json($res->decoded_content);
    ok($err->{code} eq "422", "check error code in body");
    ok($err->{message} =~ /field='status'/, "check error message in body");

    # try to create reseller with invalid status
    $req->content(JSON::to_json({
        contract_id => $new_contract_id,
        name => "test reseller $t 999",
        status => "invalid",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create reseller with invalid status");
    $err = JSON::from_json($res->decoded_content);
    ok($err->{code} eq "422", "check error code in body");
    ok($err->{message} =~ /field='status'/, "check error message in body");

    # iterate over collection to check next/prev links and status
    my $nexturi = $uri.'/api/resellers/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        is($res->code, 200, "fetch reseller page");
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        ok($selfuri eq $nexturi, "check _links.self.href of collection");
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
        ok((ref $collection->{_links}->{'ngcp:resellers'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:resellers'} eq "HASH"), "check if 'ngcp:resellers' is array/hash-ref");

        # remove any entry we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:resellers'} eq "HASH") {
            # these relations are optional:
            #ok(exists $collection->{_embedded}->{'ngcp:resellers'}->{_links}->{'ngcp:admins'}, "check presence of ngcp:admins relation");
            delete $resellers{$collection->{_links}->{'ngcp:resellers'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:resellers'} }) {
                delete $resellers{$c->{href}};
            }
            foreach my $c(@{ $collection->{_embedded}->{'ngcp:resellers'} }) {
            # these relations are optional
            #ok(exists $c->{_links}->{'ngcp:admins'}, "check presence of ngcp:admins relation");
                #ok(exists $c->{_links}->{'ngcp:billingfees'}, "check presence of ngcp:billingfees relation");
                delete $resellers{$c->{_links}->{self}->{href}};
            }
        }
             
    } while($nexturi);

    is(scalar(keys %resellers), 0, "check if all test resellers have been found");
}

# test reseller item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstreseller);
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

    $req = HTTP::Request->new('GET', $uri.'/'.$firstreseller);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one item");
    my $reseller = JSON::from_json($res->decoded_content);
    ok(exists $reseller->{id} && $reseller->{id}->is_int, "check existence of id");
    ok(exists $reseller->{contract_id} && $reseller->{contract_id}->is_int, "check existence of contract_id");
    ok(exists $reseller->{name}, "check existence of name");
    ok(exists $reseller->{status}, "check existence of status");
    
    # PUT same result again
    my $old_reseller = { %$reseller };
    delete $reseller->{_links};
    delete $reseller->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstreseller);
    
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

    # check if it fails with missing Prefer
    $req->remove_header('Prefer');
    $res = $ua->request($req);
    is($res->code, 400, "check put missing prefer");

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
    $req->content(JSON::to_json($reseller));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_reseller = JSON::from_json($res->decoded_content);
    is_deeply($old_reseller, $new_reseller, "check put if unmodified put returns the same");

    # check if we have the proper links
    # TODO: admins, sound sets etc, but we don't have those yet
    #ok(exists $new_reseller->{_links}->{'ngcp:admins'}, "check put presence of ngcp:admins relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstreseller);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => 'patched name '.$t } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched reseller item");
    my $mod_reseller = JSON::from_json($res->decoded_content);
    ok($mod_reseller->{name} eq "patched name $t", "check patched replace op");
    ok($mod_reseller->{_links}->{self}->{href} eq $firstreseller, "check patched self link");
    ok($mod_reseller->{_links}->{collection}->{href} eq '/api/resellers/', "check patched collection link");
    
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/contract_id', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef contract_id");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/contract_id', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid contract_id");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/contract_id', value => $secondcontract_id } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched existing contract_id");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "test reseller $t 2" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched existing name");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef name");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => "invalid"} ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid status");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => undef} ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef status");
}

# TODO: terminate our contracts and resellers again

done_testing;

# vim: set tabstop=4 expandtab:
