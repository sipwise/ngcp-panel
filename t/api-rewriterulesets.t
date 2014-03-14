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
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/rewriterulesets/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    ok($res->header('Accept-Post') eq "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-rewriterulesets", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

my $reseller_id = 1;

# first, we create a rewriteruleset
$req = HTTP::Request->new('POST', $uri.'/api/rewriterulesets/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
my $t = time;
$req->content(JSON::to_json({
    reseller_id => $reseller_id,
    description => "testdescription $t",
    name => "test rewriteruleset $t",
}));
$res = $ua->request($req);
is($res->code, 201, "create test rewriteruleset");
my $rewriteruleset_id = $res->header('Location');
# TODO: get it from body! -> we have no body ...
$rewriteruleset_id =~ s/^.+\/(\d+)$/$1/;
diag("set id is $rewriteruleset_id");

# then, we create a rewriterule
$req = HTTP::Request->new('POST', $uri.'/api/rewriterules/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    set_id => $rewriteruleset_id,
    description => "test rule $t",
    direction => "in",
    field => "caller",
    match_pattern => "test pattern $t",
    replace_pattern => "test_replace_$t",
}));
$res = $ua->request($req);
is($res->code, 201, "create test rewriterule");
my $rule_id = $res->header('Location');
# TODO: get it from body! -> we have no body ...
$rule_id =~ s/^.+\/(\d+)$/$1/;

# collection test
my $firstrule = undef;
my @allrules = ();
{
    # create 6 new rewriterules
    my %rules = ();
    for(my $i = 1; $i <= 6; ++$i) {
        $req = HTTP::Request->new('POST', $uri.'/api/rewriterules/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            set_id => $rewriteruleset_id,
            description => "test rule $t - $i",
            direction => "out",
            field => "callee",
            match_pattern => "test pattern $t",
            replace_pattern => "test_replace_$t",
        }));
        $res = $ua->request($req);
        is($res->code, 201, "create test rewriterule $i");
        $rules{$res->header('Location')} = 1;
        push @allrules, $res->header('Location');
        $firstrule = $res->header('Location') unless $firstrule;
    }

    # try to create ruleset without reseller_id
    $req = HTTP::Request->new('POST', $uri.'/api/rewriterulesets/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        #reseller_id => $reseller_id,
        description => "testdescription $t",
        name => "test rewriteruleset $t",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create ruleset without reseller_id");
    my $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/Invalid 'reseller_id'/, "check error message in body");

    # try to create rule with invalid set_id
    $req = HTTP::Request->new('POST', $uri.'/api/rewriterules/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        set_id => 999999,
        description => "test rule $t",
        direction => "in",
        field => "caller",
        match_pattern => "test pattern $t",
        replace_pattern => "test_replace_$t",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create rule with invalid set_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/Invalid 'set_id'/, "check error message in body");

    # try to create rule with negative set_id
    $req = HTTP::Request->new('POST', $uri.'/api/rewriterules/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        set_id => -100,
        description => "test rule $t",
        direction => "in",
        field => "caller",
        match_pattern => "test pattern $t",
        replace_pattern => "test_replace_$t",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create rule with negative set_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/Invalid 'set_id'/, "check error message in body");

    # try to create rule with missing match_pattern
    $req = HTTP::Request->new('POST', $uri.'/api/rewriterules/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        set_id => $rewriteruleset_id,
        description => "test rule $t",
        direction => "in",
        field => "caller",
        #match_pattern => "test pattern $t",
        replace_pattern => "test_replace_$t",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create rule with missing match_pattern");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/field='match_pattern'/, "check error message in body");

    # try to create rule with invalid direction and field
    $req = HTTP::Request->new('POST', $uri.'/api/rewriterules/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        set_id => $rewriteruleset_id,
        description => "test rule $t",
        direction => "foo",
        field => "bar",
        match_pattern => "test pattern $t",
        replace_pattern => "test_replace_$t",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create rule with invalid direction and field");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/field='direction'/, "check error message in body");
    like($err->{message}, qr/field='field'/, "check error message in body");

    # try to create rule without set_id
    $req = HTTP::Request->new('POST', $uri.'/api/rewriterules/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        #set_id => $rewriteruleset_id,
        description => "test rule $t",
        direction => "in",
        field => "caller",
        match_pattern => "test pattern $t",
        replace_pattern => "test_replace_$t",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create rule without set_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    like($err->{message}, qr/Required: 'set_id'/, "check error message in body");

    # iterate over rules collection to check next/prev links and status
    my $nexturi = $uri.'/api/rewriterules/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        is($res->code, 200, "fetch rules page");
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

        ok((ref $collection->{_links}->{'ngcp:rewriterules'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:rewriterules'} eq "HASH"),
            "check if 'ngcp:rewriterules' is array/hash-ref");

        # remove any entry we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:rewriterules'} eq "HASH") {
            ok(exists $collection->{_embedded}->{'ngcp:rewriterules'}->{_links}->{'ngcp:rewriterules'}, "check presence of ngcp:rewriterules relation");
            ok(exists $collection->{_embedded}->{'ngcp:rewriterules'}->{_links}->{'ngcp:rewriterulesets'}, "check presence of ngcp:rewriterulesets relation");
            delete $rules{$collection->{_links}->{'ngcp:rewriterules'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:rewriterules'} }) {
                delete $rules{$c->{href}};
            }
            foreach my $c(@{ $collection->{_embedded}->{'ngcp:rewriterules'} }) {
                ok(exists $c->{_links}->{'ngcp:rewriterules'}, "check presence of ngcp:rewriterules (self) relation");
                ok(exists $c->{_links}->{'ngcp:rewriterulesets'}, "check presence of ngcp:rewriterulesets relation");

                delete $rules{$c->{_links}->{self}->{href}};
            }
        }

    } while($nexturi);

    is(scalar(keys %rules), 0, "check if all test rewriterules have been found");
}


# test rule item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstrule);
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

    $req = HTTP::Request->new('GET', $uri.'/'.$firstrule);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one rule item");
    my $rule = JSON::from_json($res->decoded_content);
    ok(exists $rule->{direction} && $rule->{direction} =~ /^(in|out)$/ , "check existence of direction");
    ok(exists $rule->{field} && $rule->{field} =~ /^(caller|callee)$/, "check existence of field");
    ok(exists $rule->{match_pattern} && length($rule->{match_pattern}) > 0, "check existence of match_pattern");
    ok(exists $rule->{replace_pattern} && length($rule->{replace_pattern}) > 0, "check existence of replace_pattern");
    ok(exists $rule->{description} && length($rule->{description}) > 0, "check existence of description");

    # PUT same result again
    my $old_rule = { %$rule };
    delete $rule->{_links};
    delete $rule->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstrule);
    
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
    $req->content(JSON::to_json($rule));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_rule = JSON::from_json($res->decoded_content);
    is_deeply($old_rule, $new_rule, "check put if unmodified put returns the same");

    # check if we have the proper links
    ok(exists $new_rule->{_links}->{'ngcp:rewriterules'}, "check put presence of ngcp:rewriterules relation");
    ok(exists $new_rule->{_links}->{'ngcp:rewriterulesets'}, "check put presence of ngcp:rewriterulesets relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstrule);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/description', value => 'iwasmodifiedbyreplace' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched rule item");
    my $mod_rule = JSON::from_json($res->decoded_content);
    is($mod_rule->{description}, "iwasmodifiedbyreplace", "check patched replace op");
    is($mod_rule->{_links}->{self}->{href}, $firstrule, "check patched self link");
    is($mod_rule->{_links}->{collection}->{href}, '/api/rewriterules/', "check patched collection link");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/description', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef description");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/direction', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid direction");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/match_pattern', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef match_pattern");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/field', value => 'foobar' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid field");
}

{
    my $firstr;
    foreach my $r(@allrules) {
        $req = HTTP::Request->new('DELETE', $uri.'/'.$r);
        $res = $ua->request($req);
        is($res->code, 204, "check delete of rule");
        $firstr = $r unless $firstr;
    }
    $req = HTTP::Request->new('GET', $uri.'/'.$firstr);
    $res = $ua->request($req);
    is($res->code, 404, "check if deleted rule is really gone");

    $req = HTTP::Request->new('DELETE', $uri.'/api/rewriterulesets/'.$rewriteruleset_id);
    $res = $ua->request($req);
    is($res->code, 204, "check delete of rewriteruleset");

    $req = HTTP::Request->new('GET', $uri.'/api/rewriterulesets/'.$rewriteruleset_id);
    $res = $ua->request($req);
    is($res->code, 404, "check if deleted rewriteruleset is really gone");
}

done_testing;

# vim: set tabstop=4 expandtab:
