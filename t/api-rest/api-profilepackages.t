use warnings;
use strict;

use Net::Domain qw(hostfqdn);
use JSON qw();
use Test::More;
use Storable qw();
use URI::Escape qw();

use JSON::PP;
use LWP::Debug;

my $uri = $ENV{CATALYST_SERVER} || ('https://'.hostfqdn.':4443');

my ($ua, $req, $res);

use Test::Collection;
$ua = Test::Collection->new()->ua();

# OPTIONS tests
{
    $req = HTTP::Request->new('OPTIONS', $uri.'/api/profilepackages/');
    $res = $ua->request($req);
    is($res->code, 200, "check options request");
    is($res->header('Accept-Post'), "application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-profilepackages", "check Accept-Post header in options response");
    my $opts = JSON::from_json($res->decoded_content);
    my @hopts = split /\s*,\s*/, $res->header('Allow');
    ok(exists $opts->{methods} && ref $opts->{methods} eq "ARRAY", "check for valid 'methods' in body");
    foreach my $opt(qw( GET HEAD OPTIONS POST )) {
        ok(grep { /^$opt$/ } @hopts, "check for existence of '$opt' in Allow header");
        ok(grep { /^$opt$/ } @{ $opts->{methods} }, "check for existence of '$opt' in body");
    }
}


my $t = time;
my $default_reseller_id = 1;

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test profile $t",
    handle  => "testprofile$t",
    reseller_id => $default_reseller_id,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test billing profile");
my $billingprofile_uri = $uri.'/'.$res->header('Location');
$req = HTTP::Request->new('GET', $billingprofile_uri);
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed billing profile");
my $billingprofile = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test prepaid $t",
    handle  => "testprepaid$t",
    reseller_id => $default_reseller_id,
    prepaid => 1,
}));
$res = $ua->request($req);
is($res->code, 201, "POST test prepaid billing profile");
$billingprofile_uri = $uri.'/'.$res->header('Location');
$req = HTTP::Request->new('GET', $billingprofile_uri);
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed prepaid billing profile");
my $prepaid_billingprofile = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test free cash $t",
    handle  => "testfreecash$t",
    reseller_id => $default_reseller_id,
    interval_free_cash => 100
}));
$res = $ua->request($req);
is($res->code, 201, "POST test free cash billing profile");
$billingprofile_uri = $uri.'/'.$res->header('Location');
$req = HTTP::Request->new('GET', $billingprofile_uri);
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed free cash billing profile");
my $free_cash_billingprofile = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/billingprofiles/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test free time $t",
    handle  => "testfreetime$t",
    reseller_id => $default_reseller_id,
    interval_free_time => 100
}));
$res = $ua->request($req);
is($res->code, 201, "POST test free time billing profile");
$billingprofile_uri = $uri.'/'.$res->header('Location');
$req = HTTP::Request->new('GET', $billingprofile_uri);
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed free time billing profile");
my $free_time_billingprofile = JSON::from_json($res->decoded_content);

$req = HTTP::Request->new('POST', $uri.'/api/billingnetworks/');
$req->header('Content-Type' => 'application/json');
$req->header('Prefer' => 'return=representation');
$req->content(JSON::to_json({
    name => "test billing network ".$t,
    description  => "test billing network description ".$t,
    reseller_id => $default_reseller_id,
    blocks => [{ip=>'fdfe::5a55:caff:fefa:9089',mask=>128},
               {ip=>'fdfe::5a55:caff:fefa:908a'},
               {ip=>'fdfe::5a55:caff:fefa:908b',mask=>128},],
}));
$res = $ua->request($req);
is($res->code, 201, "POST test billingnetwork");
my $billingnetwork_uri = $uri.'/'.$res->header('Location');
$req = HTTP::Request->new('GET', $billingnetwork_uri);
$res = $ua->request($req);
is($res->code, 200, "fetch POSTed billingnetwork");
my $billingnetwork = JSON::from_json($res->decoded_content);

my %package_map = ();

{ #if ($enable_profile_packages) {
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test profile package " . $t,
        description  => "test profile package description " . $t,
        reseller_id => $default_reseller_id,
        initial_profiles => [{ profile_id => $billingprofile->{id}, }, ]
    }));
    $res = $ua->request($req);
    is($res->code, 201, "POST test profilepackage");
    my $profilepackage_uri = $uri.'/'.$res->header('Location');
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch POSTed profilepackage");
    my $profilepackage = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('PUT', $profilepackage_uri);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        name => "test profile package ".$t." PUT",
        description  => "test profile package description ".$t." PUT",
        #reseller_id => $reseller_id,
        initial_profiles => [{ profile_id => $billingprofile->{id}, }, ],
    }));
    $res = $ua->request($req);
    is($res->code, 200, "PUT test profilepackage");
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PUT test profilepackage");
    $profilepackage = JSON::from_json($res->decoded_content);
    
    $req = HTTP::Request->new('PATCH', $profilepackage_uri);
    $req->header('Content-Type' => 'application/json-patch+json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json(
        [ { op => 'replace', path => '/name', value => "test profile package ".$t." PATCH" } ]
    ));
    $res = $ua->request($req);
    is($res->code, 200, "PATCH test profilepackage");
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 200, "fetch PATCHed test profilepackage");
    $profilepackage = JSON::from_json($res->decoded_content);

    $req = HTTP::Request->new('DELETE', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 204, "delete profilepackage");
    
    $req = HTTP::Request->new('GET', $profilepackage_uri);
    $res = $ua->request($req);
    is($res->code, 404, "try to fetch deleted test profilepackage");
    
}

{ #if ($enable_profile_packages) {
    
    my @profile_packages = ();
    
    for (my $i = 1; $i <= 3; $i++) {
        push(@profile_packages,_post_profile_package());
    }
    
    $req = HTTP::Request->new('GET', $uri.'/api/profilepackages/?page=1&rows=5&network_name='.URI::Escape::uri_escape('*')."network $t");
    $res = $ua->request($req);
    is($res->code, 200, "filter packages by network name");
    my $collection = JSON::from_json($res->decoded_content);
    is_deeply($collection->{_embedded}->{'ngcp:profilepackages'},[ map { $_->{get}; } @profile_packages ],"compare filtered collection deeply");

    ok(_post_profile_package(initial_profiles => [{ profile_id => $prepaid_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /mixing prepaid/i, "check if mixing prepaid initial profiles is prohibited");
    ok(_post_profile_package(underrun_profiles => [{ profile_id => $prepaid_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /mixing prepaid/i, "check if mixing prepaid underrun profiles is prohibited");
    ok(_post_profile_package(topup_profiles => [{ profile_id => $prepaid_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /mixing prepaid/i, "check if mixing prepaid topup profiles is prohibited");    

    ok('HASH' eq ref _post_profile_package(topup_profiles => [{ profile_id => $billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],
                             initial_profiles => [{ profile_id => $prepaid_billingprofile->{id}, network_id => undef },
                             { profile_id => $prepaid_billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       , "check if creating a package with mixed prepaid profile sets was ok");

    ok(_post_profile_package(initial_profiles => [{ profile_id => $free_cash_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /the same interval_free_cash/i, "check if mixing free cash initial profiles is prohibited");
    ok(_post_profile_package(underrun_profiles => [{ profile_id => $free_cash_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /the same interval_free_cash/i, "check if mixing free cash underrun profiles is prohibited");
    ok(_post_profile_package(topup_profiles => [{ profile_id => $free_cash_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /the same interval_free_cash/i, "check if mixing free cash topup profiles is prohibited");    

    ok('HASH' eq ref _post_profile_package(topup_profiles => [{ profile_id => $billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],
                             initial_profiles => [{ profile_id => $free_cash_billingprofile->{id}, network_id => undef },
                             { profile_id => $free_cash_billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       , "check if creating a package with mixed free cash profile sets was ok");

    ok(_post_profile_package(initial_profiles => [{ profile_id => $free_time_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /the same interval_free_time/i, "check if mixing free time initial profiles is prohibited");
    ok(_post_profile_package(underrun_profiles => [{ profile_id => $free_time_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /the same interval_free_time/i, "check if mixing free time underrun profiles is prohibited");
    ok(_post_profile_package(topup_profiles => [{ profile_id => $free_time_billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       =~ /the same interval_free_time/i, "check if mixing free time topup profiles is prohibited");    

    ok('HASH' eq ref _post_profile_package(topup_profiles => [{ profile_id => $billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],
                             initial_profiles => [{ profile_id => $free_time_billingprofile->{id}, network_id => undef },
                             { profile_id => $free_time_billingprofile->{id}, network_id => $billingnetwork->{id}}],)
       , "check if creating a package with mixed free time profile sets was ok");
    
}

{ # expand initial_profiles, topup_profiles, underrun_profiles
    my $pkg = _post_profile_package(
        initial_profiles => [
            { profile_id => $billingprofile->{id}, network_id => undef },
            { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id} },
        ],
        topup_profiles => [
            { profile_id => $billingprofile->{id}, network_id => undef },
            { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id} },
        ],
        underrun_profiles => [
            { profile_id => $billingprofile->{id}, network_id => undef },
            { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id} },
        ],
    );
    ok(ref $pkg eq 'HASH', "create profile package for expand tests");

    my $expand = 'initial_profiles,topup_profiles,underrun_profiles';
    $req = HTTP::Request->new('GET', $pkg->{uri}.'?expand='.$expand);
    $res = $ua->request($req);
    is($res->code, 200, "GET profilepackage item with expand=$expand");
    my $expanded = JSON::from_json($res->decoded_content);

    for my $field (qw(initial_profiles topup_profiles underrun_profiles)) {
        ok(ref $expanded->{$field} eq 'ARRAY' && @{$expanded->{$field}} == 2,
            "expanded $field has two mappings");
        my ($any_net, $with_net) = @{$expanded->{$field}};

        ok(ref $any_net->{profile_id_expand} eq 'HASH',
            "$field mapping without network has profile_id_expand");
        is($any_net->{profile_id_expand}{id}, $billingprofile->{id},
            "$field mapping without network profile_id_expand.id matches");
        is($any_net->{profile_id_expand}{handle}, $billingprofile->{handle},
            "$field mapping without network profile_id_expand.handle matches");
        ok(!exists $any_net->{network_id_expand} || !defined $any_net->{network_id_expand},
            "$field mapping without network has no network_id_expand");

        ok(ref $with_net->{profile_id_expand} eq 'HASH',
            "$field mapping with network has profile_id_expand");
        is($with_net->{profile_id_expand}{id}, $billingprofile->{id},
            "$field mapping with network profile_id_expand.id matches");
        ok(ref $with_net->{network_id_expand} eq 'HASH',
            "$field mapping with network has network_id_expand");
        is($with_net->{network_id_expand}{id}, $billingnetwork->{id},
            "$field mapping with network network_id_expand.id matches");
        is($with_net->{network_id_expand}{name}, $billingnetwork->{name},
            "$field mapping with network network_id_expand.name matches");
    }

    $req = HTTP::Request->new('GET', $uri.'/api/profilepackages/?page=1&rows=10&name='.
        URI::Escape::uri_escape($pkg->{get}{name}).'&expand='.$expand);
    $res = $ua->request($req);
    is($res->code, 200, "GET profilepackages collection with expand=$expand");
    my $coll = JSON::from_json($res->decoded_content);
    my ($coll_item) = grep { $_->{id} == $pkg->{get}{id} }
        @{$coll->{_embedded}{'ngcp:profilepackages'} // []};
    ok($coll_item, "found package in expanded collection");
    ok(ref $coll_item->{initial_profiles}[0]{profile_id_expand} eq 'HASH',
        "collection expand includes initial_profiles.profile_id_expand");

    $req = HTTP::Request->new('GET', $pkg->{uri}.'?expand=not_a_real_field');
    $res = $ua->request($req);
    is($res->code, 409, "invalid expand field returns 409");
}

done_testing;

sub _post_profile_package {

    my (@further_opts) = @_;
    
    my $i = 1 + scalar keys %package_map;

    my %test_data = (post => {
        name => "test profile package ".$i . ' ' . $t,
        description  => "test profile package description ".$i . $t,
        reseller_id => $default_reseller_id,
        #status => 'active',
        initial_profiles => [{ profile_id => $billingprofile->{id}, network_id => undef },
                             { profile_id => $billingprofile->{id}, network_id => $billingnetwork->{id}}],
        initial_balance => 0.0,
        balance_interval_value => 30,
        balance_interval_unit => 'day',
        balance_interval_start_mode => 'create',
        service_charge => 0.0,
        notopup_discard_intervals => undef,
        carry_over_mode => 'carry_over',
        timely_duration_value => 7,
        timely_duration_unit => 'day',        
        underrun_profile_threshold => 0.0,
        underrun_profiles => [ { profile_id => $billingprofile->{id}, network_id => undef } ],
        underrun_lock_threshold => 0.0,
        underrun_lock_level => 4,
        topup_profiles => [ { profile_id => $billingprofile->{id}, network_id => undef } ],
        topup_lock_level => undef,
        @further_opts,
    });
    $req = HTTP::Request->new('POST', $uri.'/api/profilepackages/');
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json($test_data{post}));
    $res = $ua->request($req);
    if ($res->code == 201) {
        is($res->code, 201, "create test profile package " . $i);
        $test_data{uri} = $uri.'/'.$res->header('Location');
        $req = HTTP::Request->new('GET', $test_data{uri});
        $res = $ua->request($req);
        is($res->code, 200, "fetch test profile package " . $i);
        my $get = JSON::from_json($res->decoded_content);
        $package_map{$get->{id}} = $get;
        $test_data{get} = Storable::dclone($get);
        delete $get->{id};
        delete $get->{_links};
        is_deeply($get,$test_data{post}, "check created profile package $i deeply");
        return \%test_data;
    } else {
        my $get = JSON::from_json($res->decoded_content);
        return $get->{message};
    }

}
