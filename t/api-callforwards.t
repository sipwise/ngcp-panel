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
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/callforwards/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-callforwards", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

my $t = time;
my $reseller_id = 1;
my $billing_profile_id; #dummy

# collection test
my $firstcf = undef;
my $firstcustomer; #dummy
my $custcontact = undef; #dummy
my @allcustomers = (); #dummy
my $system_contact_id; #dummy
{
    # iterate over customers collection to check next/prev links and status
    my $nexturi = $uri.'/api/callforwards/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        is($res->code, 200, "fetch cfs page");
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
        ok((ref $collection->{_links}->{'ngcp:callforwards'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:callforwards'} eq "HASH"), "check if 'ngcp:callforwards' is array/hash-ref");

        # remove any contact we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:callforwards'} eq "HASH") {
            ok(exists $collection->{_embedded}->{'ngcp:callforwards'}->{_links}->{'ngcp:callforwards'}, "check presence of ngcp:callforwards relation");
            ok(exists $collection->{_embedded}->{'ngcp:callforwards'}->{_links}->{'ngcp:subscribers'}, "check presence of ngcp:subscribers relation");
        } else {
            foreach my $c(@{ $collection->{_embedded}->{'ngcp:callforwards'} }) {
                ok(exists $c->{_links}->{'ngcp:callforwards'}, "check presence of ngcp:callforwards relation");
                ok(exists $c->{_links}->{'ngcp:subscribers'}, "check presence of ngcp:subscribers relation");
            }
        }

    } while($nexturi);
}


diag('Note that the next tests require at least one subscriber to be present');

# fetch a callforward (subscriber) id for later tests
$req = HTTP::Request->new('GET', $uri.'/api/callforwards/?page=1&rows=1');
$res = $ua->request($req);
is($res->code, 200, "fetch first callforward");
my $cf1 = JSON::from_json($res->decoded_content);
my ($cf1_id) = $cf1->{_embedded}->{'ngcp:callforwards'}->{_links}{self}{href} =~ m!callforwards/([0-9]*)$!;

cmp_ok ($cf1_id, '>', 0, "should be positive integer");

# test cf item
{
    $req = HTTP::Request->new('OPTIONS', "$uri/api/callforwards/$cf1_id");
    $res = $ua->request($req);
    is($res->code, 200, "check options on item");
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    my $opts = JSON::from_json($res->decoded_content);
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS PUT PATCH DELETE )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
    foreach my $opt(qw( POST )) {
        ok(!grep(/^$opt$/, @hopts), "check for absence of '$opt' in Allow header");
        ok(!grep(/^$opt$/, @{ $opts->{methods} }), "check for absence of '$opt' in body");
    }

    # get our cf
    $req = HTTP::Request->new('GET', "$uri/api/callforwards/$cf1_id");
    
    $res = $ua->request($req);
    is($res->code, 200, "fetch cf id $cf1_id");
    my $cf1single = JSON::from_json($res->decoded_content);
    is(ref $cf1single, "HASH", "cf should be hash");
    ok(exists $cf1single->{cfu}, "cf should have key cfu");
    ok(exists $cf1single->{cfb}, "cf should have key cfb");
    ok(exists $cf1single->{cft}, "cf should have key cft");
    ok(exists $cf1single->{cfna}, "cf should have key cfna");

    # write this cf
    $req = HTTP::Request->new('PUT', "$uri/api/callforwards/$cf1_id");
    $req->header('Prefer' => "return=representation");
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        cfu => {
            destinations => [
                { destination => "12345", timeout => 200},
            ],
            times => undef,
        },
        cft => {
            destinations => [
                { destination => "5678" },
                { destination => "voicebox", timeout => 500 },
            ],
            ringtimeout => 10,
        }
    }));
    $res = $ua->request($req);
    is($res->code, 200, "write a specific callforward") || diag ($res->message);
    my $cf1put = JSON::from_json($res->decoded_content);
    is (ref $cf1put, "HASH", "should be hashref");
    is ($cf1put->{cfu}{destinations}->[0]->{timeout}, 200, "Check timeout of cft");
    like ($cf1put->{cft}{destinations}->[0]->{destination}, qr/^sip:5678/, "Check first destination of cft");
    is ($cf1put->{cft}{destinations}->[1]->{destination}, "voicebox", "Check second destination of cft");

    #write invalid 'timeout'
    $req = HTTP::Request->new('PUT', "$uri/api/callforwards/$cf1_id");
    $req->header('Prefer' => "return=representation");
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        cfu => {
            destinations => [
                { destination => "12345", timeout => "foobar"},
            ],
            times => undef,
        },
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create customer with invalid type");
    my $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/Validation failed/, "check error message in body");

    # get invalid cf
    $req = HTTP::Request->new('GET', "$uri/api/callforwards/abc");
    $res = $ua->request($req);
    is($res->code, 400, "try invalid callforward id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "400", "check error code in body");
    like($err->{message}, qr/Invalid id/, "check error message in body");

    # PUT same result again
    my $old_cf1 = { %$cf1put };
    delete $cf1put->{_links};
    delete $cf1put->{_embedded};
    $req = HTTP::Request->new('PUT', "$uri/api/callforwards/$cf1_id");
    
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
    $req->content(JSON::to_json($cf1put));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_cf1 = JSON::from_json($res->decoded_content);
    is_deeply($old_cf1, $new_cf1, "check put if unmodified put returns the same");

    # check if we have the proper links
    ok(exists $new_cf1->{_links}->{'ngcp:callforwards'}, "check put presence of ngcp:customercontacts relation");
    ok(exists $new_cf1->{_links}->{'ngcp:subscribers'}, "check put presence of ngcp:billingprofiles relation");


    $req = HTTP::Request->new('PATCH', "$uri/api/callforwards/$cf1_id");
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/cfu/destinations/0/timeout', value => '123' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched cf item");
    my $mod_cf1 = JSON::from_json($res->decoded_content);
    is($mod_cf1->{cfu}{destinations}->[0]->{timeout}, "123", "check patched replace op");
    is($mod_cf1->{_links}->{self}->{href}, "/api/callforwards/$cf1_id", "check patched self link");
    is($mod_cf1->{_links}->{collection}->{href}, '/api/callforwards/', "check patched collection link");


    $req->content(JSON::to_json(
        [ { op => 'add', path => '/cfu/destinations/-', value => {destination => 99999} } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patch, add a cfu destination");


    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/cfu/destinations/0/timeout', value => "" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef timeout");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/cfu/destinations/0/timeout', value => 'invalid' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid status");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/some/path', value => 'invalid' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid path");
}

done_testing;

# vim: set tabstop=4 expandtab:
