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
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/billingfees/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-billingfees", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

my $reseller_id = 1;

# first, we need a billing profile
$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
my $t = time;
$req->content(JSON::to_json({
    reseller_id => $reseller_id,
    handle => "testapihandle$t",
    name => "test api name $t",
}));
$res = $ua->request($req);
is($res->code, 201, "create test billing profile");
my $billing_profile_id = $res->header('Location');
# TODO: get it from body!
$billing_profile_id =~ s/^.+\/(\d+)$/$1/;

# then, we need a billing zone
$req = HTTP::Request->new('POST', $uri.'/api/billingzones/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    billing_profile_id => $billing_profile_id,
    zone => "testzone",
    detail => "test zone from api",
}));
$res = $ua->request($req);
is($res->code, 201, "create test billing zone");
my $billing_zone_id = $res->header('Location');
# TODO: get it from body!
$billing_zone_id =~ s/^.+\/(\d+)$/$1/;

# collection test
my $firstfee = undef;
my @allfees = ();
{
    # create 6 new billing profiles
    my %fees = ();
    for(my $i = 1; $i <= 6; ++$i) {
        $req = HTTP::Request->new('POST', $uri.'/api/billingfees/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            billing_profile_id => $billing_profile_id,
            billing_zone_id => $billing_zone_id,
            destination => "^1234$i",
            direction => "out",
            onpeak_init_rate => 1,
            onpeak_init_interval => 60,
            onpeak_follow_rate => 1,
            onpeak_follow_interval => 30,
            offpeak_init_rate => 0.5,
            offpeak_init_interval => 60,
            offpeak_follow_rate => 0.5,
            offpeak_follow_interval => 30,
        }));
        $res = $ua->request($req);
        is($res->code, 201, "create test billing fee $i");
        $fees{$res->header('Location')} = 1;
        push @allfees, $res->header('Location');
        $firstfee = $res->header('Location') unless $firstfee;
    }

    # try to create fee without billing_profile_id
    $req = HTTP::Request->new('POST', $uri.'/api/billingfees/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        #billing_profile_id => $billing_profile_id,
        billing_zone_id => $billing_zone_id,
        destination => "^1234",
        direction => "out",
        onpeak_init_rate => 1,
        onpeak_init_interval => 60,
        onpeak_follow_rate => 1,
        onpeak_follow_interval => 30,
        offpeak_init_rate => 0.5,
        offpeak_init_interval => 60,
        offpeak_follow_rate => 0.5,
        offpeak_follow_interval => 30,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create profile without billing_profile_id");
    my $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Missing parameter 'billing_profile_id'/, "check error message in body");

    # try to create fee with invalid billing_profile_id
    $req = HTTP::Request->new('POST', $uri.'/api/billingfees/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        billing_profile_id => 99999,
        billing_zone_id => $billing_zone_id,
        destination => "^1234",
        direction => "out",
        onpeak_init_rate => 1,
        onpeak_init_interval => 60,
        onpeak_follow_rate => 1,
        onpeak_follow_interval => 30,
        offpeak_init_rate => 0.5,
        offpeak_init_interval => 60,
        offpeak_follow_rate => 0.5,
        offpeak_follow_interval => 30,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create profile with invalid billing_profile_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'billing_profile_id'/, "check error message in body");

    # try to create fee with missing billing_zone_id
    $req = HTTP::Request->new('POST', $uri.'/api/billingfees/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        billing_profile_id => $billing_profile_id,
        #billing_zone_id => $billing_zone_id,
        destination => "^1234",
        direction => "out",
        onpeak_init_rate => 1,
        onpeak_init_interval => 60,
        onpeak_follow_rate => 1,
        onpeak_follow_interval => 30,
        offpeak_init_rate => 0.5,
        offpeak_init_interval => 60,
        offpeak_follow_rate => 0.5,
        offpeak_follow_interval => 30,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create profile without billing_zone_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'billing_zone_id'/, "check error message in body");

    # try to create fee with invalid billing_zone_id
    $req = HTTP::Request->new('POST', $uri.'/api/billingfees/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        billing_profile_id => $billing_profile_id,
        billing_zone_id => 99999,
        destination => "^1234",
        direction => "out",
        onpeak_init_rate => 1,
        onpeak_init_interval => 60,
        onpeak_follow_rate => 1,
        onpeak_follow_interval => 30,
        offpeak_init_rate => 0.5,
        offpeak_init_interval => 60,
        offpeak_follow_rate => 0.5,
        offpeak_follow_interval => 30,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create profile without billing_profile_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid 'billing_zone_id'/, "check error message in body");

    # TODO: check for wrong values in rates, prepaid etc

    # iterate over fees collection to check next/prev links and status
    my $nexturi = $uri.'/api/billingfees/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        is($res->code, 200, "fetch fees page");
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
        ok((ref $collection->{_links}->{'ngcp:billingfees'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:billingfees'} eq "HASH"), "check if 'ngcp:billingfees' is array/hash-ref");

        # remove any entry we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:billingfees'} eq "HASH") {
            ok(exists $collection->{_embedded}->{'ngcp:billingfees'}->{_links}->{'ngcp:billingprofiles'}, "check presence of ngcp:billingprofiles relation");
            ok(exists $collection->{_embedded}->{'ngcp:billingfees'}->{_links}->{'ngcp:billingzones'}, "check presence of ngcp:billingzones relation");
            delete $fees{$collection->{_links}->{'ngcp:billingfees'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:billingfees'} }) {
                delete $fees{$c->{href}};
            }
            foreach my $c(@{ $collection->{_embedded}->{'ngcp:billingfees'} }) {
                ok(exists $c->{_links}->{'ngcp:billingprofiles'}, "check presence of ngcp:billingprofiles relation");
                ok(exists $c->{_links}->{'ngcp:billingzones'}, "check presence of ngcp:billingzones relation");

                delete $fees{$c->{_links}->{self}->{href}};
            }
        }
             
    } while($nexturi);

    is(scalar(keys %fees), 0, "check if all test billing fees have been found");

    # try to create fee with implicit zone which already exists
    $req = HTTP::Request->new('POST', $uri.'/api/billingfees/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        billing_profile_id => $billing_profile_id,
        billing_zone_zone => 'testzone',
        billing_zone_detail => 'test zone from api',
        destination => "^1234",
        direction => "out",
        onpeak_init_rate => 1,
        onpeak_init_interval => 60,
        onpeak_follow_rate => 1,
        onpeak_follow_interval => 30,
        offpeak_init_rate => 0.5,
        offpeak_init_interval => 60,
        offpeak_follow_rate => 0.5,
        offpeak_follow_interval => 30,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create profile fee with existing implicit zone");
    $req = HTTP::Request->new('GET', $uri.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch profile fee with existing implicit zone");
    my $z_fee = JSON::from_json($res->decoded_content);
    ok(exists $z_fee->{billing_zone_id} && $z_fee->{billing_zone_id} == $billing_zone_id, "check if implicit zone returns the correct zone id");
    
    $req = HTTP::Request->new('DELETE', $uri.$z_fee->{_links}->{'self'}->{href});
    $res = $ua->request($req);
    is($res->code, 204, "delete fee of existing implicit zone");

    # try to create fee with implicit zone which doesn't exist yet
    my $t = time;
    $req = HTTP::Request->new('POST', $uri.'/api/billingfees/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        billing_profile_id => $billing_profile_id,
        billing_zone_zone => 'testzone new'.$t,
        billing_zone_detail => 'test zone from api new'.$t,
        destination => "^1234",
        direction => "out",
        onpeak_init_rate => 1,
        onpeak_init_interval => 60,
        onpeak_follow_rate => 1,
        onpeak_follow_interval => 30,
        offpeak_init_rate => 0.5,
        offpeak_init_interval => 60,
        offpeak_follow_rate => 0.5,
        offpeak_follow_interval => 30,
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create profile fee with new implicit zone");
    $req = HTTP::Request->new('GET', $uri.$res->header('Location'));
    $res = $ua->request($req);
    is($res->code, 200, "fetch profile fee with new implicit zone");
    $z_fee = JSON::from_json($res->decoded_content);
    ok(exists $z_fee->{billing_zone_id} && $z_fee->{billing_zone_id} > $billing_zone_id, "check if implicit zone returns a new zone id");

    $req = HTTP::Request->new('DELETE', $uri.$z_fee->{_links}->{'ngcp:billingzones'}->{href});
    $res = $ua->request($req);
    is($res->code, 204, "delete new implicit zone");

    $req = HTTP::Request->new('GET', $uri.$z_fee->{_links}->{'self'}->{href});
    $res = $ua->request($req);
    is($res->code, 404, "check if fee is deleted when zone is deleted");
}



# test fee item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstfee);
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

    $req = HTTP::Request->new('GET', $uri.'/'.$firstfee);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one fee item");
    my $fee = JSON::from_json($res->decoded_content);
    ok(exists $fee->{billing_profile_id} && $fee->{billing_profile_id} == $billing_profile_id, "check existence of billing_profile_id");
    ok(exists $fee->{billing_zone_id} && $fee->{billing_zone_id} == $billing_zone_id, "check existence of billing_zone_id");
    ok(exists $fee->{direction} && $fee->{direction} =~ /^(in|out)$/ , "check existence of direction");
    ok(exists $fee->{source} && length($fee->{source}) > 0, "check existence of source");
    ok(exists $fee->{destination} && length($fee->{destination}) > 0, "check existence of destination");
    
    # PUT same result again
    my $old_fee = { %$fee };
    delete $fee->{_links};
    delete $fee->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstfee);

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
    $req->content(JSON::to_json($fee));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_fee = JSON::from_json($res->decoded_content);
    is_deeply($old_fee, $new_fee, "check put if unmodified put returns the same");

    # check if we have the proper links
    ok(exists $new_fee->{_links}->{'ngcp:billingprofiles'}, "check put presence of ngcp:billingprofiles relation");
    ok(exists $new_fee->{_links}->{'ngcp:billingzones'}, "check put presence of ngcp:billingzones relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstfee);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/direction', value => 'in' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched fee item");
    my $mod_fee = JSON::from_json($res->decoded_content);
    is($mod_fee->{direction}, "in", "check patched replace op");
    is($mod_fee->{_links}->{self}->{href}, $firstfee, "check patched self link");
    is($mod_fee->{_links}->{collection}->{href}, '/api/billingfees/', "check patched collection link");
    
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
        [ { op => 'replace', path => '/billing_zone_id', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef billing_zone_id");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/billing_zone_id', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid billing_zone_id");
}

{
    my $ff;
    foreach my $f(@allfees) {
        $req = HTTP::Request->new('DELETE', $uri.'/'.$f);
        $res = $ua->request($req);
        is($res->code, 204, "check delete of fee");
        $ff = $f unless $ff;
    }
    $req = HTTP::Request->new('GET', $uri.'/'.$ff);
    $res = $ua->request($req);
    is($res->code, 404, "check if deleted fee is really gone");

    $req = HTTP::Request->new('DELETE', $uri.'/api/billingzones/'.$billing_zone_id);
    $res = $ua->request($req);
    is($res->code, 204, "check delete of zone");

    $req = HTTP::Request->new('GET', $uri.'/api/billingzones/'.$billing_zone_id);
    $res = $ua->request($req);
    is($res->code, 404, "check if deleted zone is really gone");
}

done_testing;

# vim: set tabstop=4 expandtab:
