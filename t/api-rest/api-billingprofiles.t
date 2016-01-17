use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

my $is_local_env = 0;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');
my ($netloc) = ($uri =~ m!^https?://(.*)/?.*$!);

my ($ua, $req, $res);
$ua = LWP::UserAgent->new;

$ua->ssl_opts(
        verify_hostname => 0,
        SSL_verify_mode => 0,
    );
my $user = $ENV{API_USER} // 'administrator';
my $pass = $ENV{API_PASS} // 'administrator';
$ua->credentials($netloc, "api_admin_http", $user, $pass);

# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/billingprofiles/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-billingprofiles", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep(/^$opt$/, @hopts), "check for existence of '$opt' in Allow header");
        ok(grep(/^$opt$/, @{ $opts->{methods} }), "check for existence of '$opt' in body");
    }
}

my $reseller_id = 1;

# collection test
my $firstprofile = undef;
my @allprofiles = ();
{
    # create 6 new billing profiles
    my %profiles = ();
    for(my $i = 1; $i <= 6; ++$i) {
        $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
        $req->header('Content-Type' => 'application/json');
        $req->content(JSON::to_json({
            reseller_id => $reseller_id,
            handle => "testapihandle$i".time,
            name => "test api name $i".time,
        }));
        $res = $ua->request($req);
        is($res->code, 201, "create test billing profile $i");
        $profiles{$res->header('Location')} = 1;
        push @allprofiles, $res->header('Location');
        $firstprofile = $res->header('Location') unless $firstprofile;
    }

    # try to create profile without reseller_id
    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        handle => "testapihandle",
        name => "test api name",
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create profile without reseller_id");
    my $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='reseller_id'/, "check error message in body");

    # try to create profile with empty reseller_id
    $req->content(JSON::to_json({
        handle => "testapihandle",
        name => "test api name",
        reseller_id => undef,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create profile with empty reseller_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='reseller_id'/, "check error message in body");

    # try to create profile with invalid reseller_id
    $req->content(JSON::to_json({
        handle => "testapihandle",
        name => "test api name",
        reseller_id => 99999,
    }));
    $res = $ua->request($req);
    is($res->code, 422, "create profile with invalid reseller_id");
    $err = JSON::from_json($res->decoded_content);
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /Invalid reseller/, "check error message in body");

    # TODO: check for wrong values in prepaid, fees etc

    # iterate over contracts collection to check next/prev links and status
    my $nexturi = $uri.'/api/billingprofiles/?page=1&rows=5';
    do {
        $res = $ua->get($nexturi);
        is($res->code, 200, "fetch profile page");
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
        ok((ref $collection->{_links}->{'ngcp:billingprofiles'} eq "ARRAY" ||
            ref $collection->{_links}->{'ngcp:billingprofiles'} eq "HASH"), "check if 'ngcp:billingprofiles' is array/hash-ref");

        # remove any entry we find in the collection for later check
        if(ref $collection->{_links}->{'ngcp:billingprofiles'} eq "HASH") {
            # these relations are only there if we have zones/fees, which is not the case with an empty profile
            #ok(exists $collection->{_embedded}->{'ngcp:billingprofiles'}->{_links}->{'ngcp:billingfees'}, "check presence of ngcp:billingfees relation");
            #ok(exists $collection->{_embedded}->{'ngcp:billingprofiles'}->{_links}->{'ngcp:billingzones'}, "check presence of ngcp:billingzones relation");
            delete $profiles{$collection->{_links}->{'ngcp:billingprofiles'}->{href}};
        } else {
            foreach my $c(@{ $collection->{_links}->{'ngcp:billingprofiles'} }) {
                delete $profiles{$c->{href}};
            }
            foreach my $c(@{ $collection->{_embedded}->{'ngcp:billingprofiles'} }) {
            # these relations are only there if we have zones/fees, which is not the case with an empty profile
            #ok(exists $collection->{_embedded}->{'ngcp:billingprofiles'}->{_links}->{'ngcp:billingfees'}, "check presence of ngcp:billingfees relation");
                #ok(exists $c->{_links}->{'ngcp:billingfees'}, "check presence of ngcp:billingfees relation");
                #ok(exists $c->{_links}->{'ngcp:billingzones'}, "check presence of ngcp:billingzones relation");

                delete $profiles{$c->{_links}->{self}->{href}};
            }
        }

    } while($nexturi);

    is(scalar(keys %profiles), 0, "check if all test billing profiles have been found");
}

# test profile item
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/'.$firstprofile);
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

    $req = HTTP::Request->new('GET', $uri.'/'.$firstprofile);
    $res = $ua->request($req);
    is($res->code, 200, "fetch one profile item");
    my $profile = JSON::from_json($res->decoded_content);
    ok(exists $profile->{reseller_id} && $profile->{reseller_id} > 0, "check existence of reseller_id");
    ok(exists $profile->{handle}, "check existence of handle");
    ok(exists $profile->{name}, "check existence of name");

    # PUT same result again
    my $old_profile = { %$profile };
    delete $profile->{_links};
    delete $profile->{_embedded};
    $req = HTTP::Request->new('PUT', $uri.'/'.$firstprofile);

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
    $req->content(JSON::to_json($profile));
    $res = $ua->request($req);
    is($res->code, 200, "check put successful");

    my $new_profile = JSON::from_json($res->decoded_content);
    is_deeply($old_profile, $new_profile, "check put if unmodified put returns the same");

    # check if we have the proper links
    # TODO: fees, reseller links
    #ok(exists $new_contract->{_links}->{'ngcp:resellers'}, "check put presence of ngcp:resellers relation");

    $req = HTTP::Request->new('PATCH', $uri.'/'.$firstprofile);
    $req->header('Prefer' => 'return=representation');
    $req->header('Content-Type' => 'application/json-patch+json');
    my $t = time;
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => 'patched name '.$t } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched profile item");
    my $mod_profile = JSON::from_json($res->decoded_content);
    is($mod_profile->{name}, "patched name $t", "check patched replace op");
    is($mod_profile->{_links}->{self}->{href}, $firstprofile, "check patched self link");
    is($mod_profile->{_links}->{collection}->{href}, '/api/billingprofiles/', "check patched collection link");


    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/reseller_id', value => undef } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched undef reseller");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/reseller_id', value => 99999 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 422, "check patched invalid reseller");

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/prepaid', value => 1 } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "check patched prepaid");

    # TODO: invalid handle etc

    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/status', value => 'terminated' } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "terminated profile successful");
    $req = HTTP::Request->new('GET', $uri.'/'.$firstprofile);
    $res = $ua->request($req);
    is($res->code, 404, "try to fetch terminated profile");
}

{
    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        reseller_id => $reseller_id,
        handle => "peakweekdays".time,
        name => "peak weekdays ".time,
        peaktime_weekdays => [
            { weekday => 1,
              start => '08:00',
              stop => '10:00',
            },
            { weekday => 1,
              start => '10:01',
              stop => '12:00',
            },
            { weekday => 2,
              start => '10:00',
              stop => '12:00',
            },
        ],
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create peaktimes weekday billing profile");
    my $profile_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profile");
    my $profile = JSON::from_json($res->decoded_content);

    my $old_profile = { %$profile };
    delete $profile->{_links};
    delete $profile->{_embedded};
    $req = HTTP::Request->new('PUT', $profile_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');

    my $malformed_profile = { %$profile };
    $malformed_profile->{peaktime_weekdays} = [
            { weekday => 1,
              start => '08:00',
              stop => '10:00',
            },
            { weekday => 1,
              start => '10:00',
              stop => '12:00',
            },];
    $req->content(JSON::to_json($malformed_profile));
    $res = $ua->request($req);
    is($res->code, 422, "try to update profile using overlapping weekday peaktimes");
    my $err = JSON::from_json($res->decoded_content);
    ok($err->{message} =~ /overlap/, "check error message in body");

    $req->content(JSON::to_json($profile));
    $res = $ua->request($req);
    is($res->code, 200, "check get2put weekday peaktimes successful");
    my $got = JSON::from_json($res->decoded_content);
    delete $got->{_links};
    delete $got->{_embedded};
    is_deeply($got,$profile,"check get2put weekday peaktimes deeply");

}

PEAK:
{
    $req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        reseller_id => $reseller_id,
        handle => "peakspecials".time,
        name => "peak specials ".time,
        peaktime_special => [
            { start => '2016-01-01 08:00:00',
              stop => '2016-01-02 07:59:59',
            },
            { start => '2016-01-02 08:00:00',
              stop => '2016-01-02 10:00:00',
            },
        ],
    }));
    $res = $ua->request($req);
    is($res->code, 201, "create peaktimes special billing profile");
    my $profile_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profile_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profile");
    my $profile = JSON::from_json($res->decoded_content);

    my $old_profile = { %$profile };
    delete $profile->{_links};
    delete $profile->{_embedded};
    $req = HTTP::Request->new('PUT', $profile_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');

    my $malformed_profile = { %$profile };
    $malformed_profile->{peaktime_special} = [
            { start => '2016-01-01 08:00:00',
              stop => '2016-01-02 08:00:00',
            },
            { start => '2016-01-02 08:00:00',
              stop => '2016-01-02 08:00:01',
            },];
    $req->content(JSON::to_json($malformed_profile));
    $res = $ua->request($req);
    is($res->code, 422, "try to update profile using overlapping special peaktimes");
    my $err = JSON::from_json($res->decoded_content);
    ok($err->{message} =~ /overlap/, "check error message in body");

    $req->content(JSON::to_json($profile));
    $res = $ua->request($req);
    is($res->code, 200, "check get2put special peaktimes successful");
    my $got = JSON::from_json($res->decoded_content);
    delete $got->{_links};
    delete $got->{_embedded};
    is_deeply($got,$profile,"check get2put special peaktimes deeply");

}

done_testing;

# vim: set tabstop=4 expandtab:
