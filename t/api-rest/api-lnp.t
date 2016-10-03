use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;
use DateTime::Format::ISO8601;
use Data::Dumper;
use DateTime;

use warnings;

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

#$ua->add_handler("request_send",  sub {
#    my ($request, $ua, $h) = @_;
#    print $request->method . ' ' . $request->uri . "\n" . ($request->content ? $request->content . "\n" : '') unless $request->header('authorization');
#    return undef;
#});
#$ua->add_handler("response_done", sub {
#    my ($response, $ua, $h) = @_;
#    print $response->decoded_content . "\n" if $response->code != 401;
#    return undef;
#});

my $t = time;

my %carrier_map = ();
my %number_map = ();

#{ #regular case
#    my $carrier1 = _create_lnp_provider();
#    my $number1 = _create_lnp_number($carrier1, number => '123'.$t);
#    my $number2 = _create_lnp_number($carrier1, number => '456'.$t);
#    _delete_lnp_number($number1);
#    _delete_lnp_number($number2);
#    _delete_lnp_provider($carrier1);
#}
#
#$t += 1;
#
#{ #delete provider with numbers left:
#    my $carrier1 = _create_lnp_provider();
#    my $number1 = _create_lnp_number($carrier1, number => '123'.$t);
#    _delete_lnp_provider($carrier1, 500);
#}
#
#$t += 1;

{
    my $carrier1 = _create_lnp_provider();
    my $carrier2 = _create_lnp_provider();
    my $number = '123'.$t;
    my $now = DateTime->now();
    my $start1 = $now->clone->subtract(days=>1);
    my $start2 = $now->clone->subtract(days=>2);
    my $end = $now->clone->add(days=>1);
    my $number1 = _create_lnp_number($carrier1, number => $number, start => $start1->ymd, end => $end->ymd);
    my $number2 = _create_lnp_number($carrier2, number => $number, start => $start2->ymd, end => $end->ymd);

    _check_lnpnumber_history("total history of number $number: ",$number,[
        { carrier_id => $carrier2->{id}, start => $start2->ymd, end => $end->ymd },
        { carrier_id => $carrier1->{id}, start => $start1->ymd, end => $end->ymd },
    ],undef);

    _check_lnpnumber_history("actual number $number before it was registered at all: ",$number,[
    ],$now->clone->subtract(days=>3));

    _check_lnpnumber_history("actual number $number after registration for first carrier: ",$number,[
        { carrier_id => $carrier1->{id}, },
    ],$now->clone->subtract(days=>1)->add(hours=>1));

    _check_lnpnumber_history("actual number $number after registration for second carrier: ",$number,[
        { carrier_id => $carrier2->{id}, },
    ],$now->clone->subtract(days=>2)->add(hours=>1));

    _check_lnpnumber_history("actual number $number now: ",$number,[
        { carrier_id => $carrier1->{id}, },
    ],"");

    _check_lnpnumber_history("actual number $number beyond/'terminated': ",$number,[
    ],$end->clone->add(days => 1)); #23:59 vs 00:00
}

$t += 1;

{ #unique number - insert:
    my $carrier1 = _create_lnp_provider();
    my $number1 = _create_lnp_number($carrier1, number => '123'.$t);
    my $number2 = _create_lnp_number($carrier1, number => '123'.$t, expected_code => 422);
    #_delete_lnp_provider($carrier1, expected_code => 500);
}

$t += 1;

{ #unique number - update:
    my $carrier1 = _create_lnp_provider();
    my $number1 = _create_lnp_number($carrier1, number => '123'.$t);
    my $number2 = _create_lnp_number($carrier1, number => '1234'.$t);
    _update_lnp_number($number2, number => '123'.$t, expected_code => 422);
}

#todo: multithread insert testcase

sub _create_lnp_number {

    my $carrier = shift;
    my (%further_opts) = @_;
    my $expected_code = delete $further_opts{expected_code} // 201;
    $req = HTTP::Request->new('POST', $uri.'/api/lnpnumbers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        carrier_id => $carrier->{id},
        number => 'test'.$t,
        %further_opts,
    }));
    $res = $ua->request($req);
    if ($expected_code eq '201') {
        is($res->code, 201, "create test lnp number");
        $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
        $res = $ua->request($req);
        is($res->code, 200, "fetch test lnp number");
        my $number = JSON::from_json($res->decoded_content);
        $number_map{$carrier->{id}} = $number;
        return $number;
    } else {
        is($res->code, $expected_code, "create test lnp number returns $expected_code");
        return undef;
    }

}

sub _update_lnp_number {

    my $number = shift;
    my (%further_opts) = @_;
    my $expected_code = delete $further_opts{expected_code} // 200;
    my $url = $uri.'/api/lnpnumbers/'.$number->{id};
    $req = HTTP::Request->new('PUT', $url);
    $req->header('Content-Type' => 'application/json');
    $req->header('Prefer' => 'return=representation');
    $req->content(JSON::to_json({
        %$number,
        %further_opts,
    }));
    $res = $ua->request($req);
    if ($expected_code eq '200') {
        is($res->code, 200, "update test lnp number");
        $number = JSON::from_json($res->decoded_content);
        $number_map{$number->{id}} = $number;
        return $number;
    } else {
        is($res->code, $expected_code, "update test lnp number returns $expected_code");
        $req = HTTP::Request->new('GET', $url);
        $res = $ua->request($req);
        is($res->code, 200, "fetch test lnp number");
        my $got_number = JSON::from_json($res->decoded_content);
        is_deeply($got_number,$number,"lnp number unchanged");
        return undef;
    }
}

sub _delete_lnp_number {

    my ($number,$expected_code) = @_;
    $expected_code //= 204;
    my $url = $uri.'/api/lnpnumbers/'.$number->{id};
    $req = HTTP::Request->new('DELETE', $url);
    $res = $ua->request($req);
    if ($expected_code eq '204') {
        is($res->code, 204, "delete test lnp number");
        $req = HTTP::Request->new('GET', $url);
        $res = $ua->request($req);
        is($res->code, 404, "test lnp number is not found");
        return delete $number_map{$number->{id}};
    } else {
        is($res->code, $expected_code, "create test lnp number returns $expected_code");
        $req = HTTP::Request->new('GET', $url);
        $res = $ua->request($req);
        is($res->code, 200, "test lnp number is still found");
        return undef;
    }

}

sub _create_lnp_provider {

    my (%further_opts) = @_;
    my $expected_code = delete $further_opts{expected_code} // 201;
    $req = HTTP::Request->new('POST', $uri.'/api/lnpcarriers/');
    $req->header('Content-Type' => 'application/json');
    $req->content(JSON::to_json({
        #skip_rewrite => JSON::false,
        name => "test_lnp_carrier_".(scalar keys %carrier_map).'_'.$t,
        prefix => 'test'.$t,
        %further_opts,
    }));
    $res = $ua->request($req);
    if ($expected_code eq '201') {
        is($res->code, 201, "create test lnp carrier");
        $req = HTTP::Request->new('GET', $uri.'/'.$res->header('Location'));
        $res = $ua->request($req);
        is($res->code, 200, "fetch test lnp carrier");
        my $carrier = JSON::from_json($res->decoded_content);
        $carrier_map{$carrier->{id}} = $carrier;
        return $carrier;
    } else {
        is($res->code, $expected_code, "create test lnp carrier returns $expected_code");
        return undef;
    }

}

sub _delete_lnp_provider {

    my ($carrier,$expected_code) = @_;
    $expected_code //= 204;
    my $url = $uri.'/api/lnpcarriers/'.$carrier->{id};
    $req = HTTP::Request->new('DELETE', $url);
    $res = $ua->request($req);
    if ($expected_code eq '204') {
        is($res->code, 204, "delete test lnp carrier");
        $req = HTTP::Request->new('GET', $url);
        $res = $ua->request($req);
        is($res->code, 404, "test lnp carrier is not found");
        return delete $carrier_map{$carrier->{id}};
    } else {
        is($res->code, $expected_code, "create test lnp carrier returns $expected_code");
        $req = HTTP::Request->new('GET', $url);
        $res = $ua->request($req);
        is($res->code, 200, "test lnp carrier is still found");
        return undef;
    }

}

sub _check_lnpnumber_history {

    my ($label,$number,$expected_lnpnumbers,$actual) = @_;
    if (defined $actual) {
        eval { $actual = DateTime::Format::ISO8601->parse_datetime($actual); };
        $actual = '&actual=' . $actual;
    } else {
        $actual = '';
    }
    if (defined $number) {
        $number = '&number=' . $number;
    } else {
        $number = '';
    }

    my $total_count = (scalar @$expected_lnpnumbers);
    my $i = 0;
    my $ok = 1;
    my @lnpnumbers = ();
    my @requests = ();
    my $last_request;
    $last_request = _req_to_debug($req) if $req;
    my $nexturi = $uri.'/api/lnpnumbers/?page=1&rows=10&order_by_direction=asc&order_by=start'.$actual.$number;
    do {
        $req = HTTP::Request->new('GET',$nexturi);
        $res = $ua->request($req);
        is($res->code, 200, $label . "fetch lnpnumbers collection page");
        push(@requests,_req_to_debug($req));
        my $collection = JSON::from_json($res->decoded_content);
        my $selfuri = $uri . $collection->{_links}->{self}->{href};
        my $colluri = URI->new($selfuri);

        $ok = ok($collection->{total_count} == $total_count, $label . "check 'total_count' of collection") && $ok;

        #my %q = $colluri->query_form;
        #ok(exists $q{page} && exists $q{rows}, $label . "check existence of 'page' and 'row' in 'self'");
        #my $page = int($q{page});
        #my $rows = int($q{rows});
        #if($page == 1) {
        #    ok(!exists $collection->{_links}->{prev}->{href}, $label . "check absence of 'prev' on first page");
        #} else {
        #    ok(exists $collection->{_links}->{prev}->{href}, $label . "check existence of 'prev'");
        #}
        #if(($collection->{total_count} / $rows) <= $page) {
        #    ok(!exists $collection->{_links}->{next}->{href}, $label . "check absence of 'next' on last page");
        #} else {
        #    ok(exists $collection->{_links}->{next}->{href}, $label . "check existence of 'next'");
        #}

        if($collection->{_links}->{next}->{href}) {
            $nexturi = $uri . $collection->{_links}->{next}->{href};
        } else {
            $nexturi = undef;
        }

        # TODO: I'd expect that to be an array ref in any case!
        #ok(ref $collection->{_links}->{'ngcp:lnpnumbers'} eq "ARRAY", $label . "check if 'ngcp:lnpnumbers' is array");

        $collection->{_embedded}->{'ngcp:lnpnumbers'} = [
            $collection->{_embedded}->{'ngcp:lnpnumbers'}
        ] if "HASH" eq ref $collection->{_embedded}->{'ngcp:lnpnumbers'};

        my $page_items = {};

        foreach my $lnpnumber (@{ $collection->{_embedded}->{'ngcp:lnpnumbers'} }) {
            #ok(exists $page_items->{$interval->{id}},$label . "check existence of linked item among embedded");
            #my $fetched = delete $page_items->{$interval->{id}};
            #delete $fetched->{content};
            #is_deeply($interval,$fetched,$label . "compare fetched and embedded item deeply");


            $ok = _compare_lnpnumber($lnpnumber,$expected_lnpnumbers->[$i],$label) && $ok;
            delete $lnpnumber->{'_links'};
            push(@lnpnumbers,$lnpnumber);
            $i++
        }

    } while($nexturi);

    ok($i == $total_count,$label . "check if all expected items are listed");
    diag(Dumper({last_request => $last_request, collection_requests => \@requests, result => \@lnpnumbers})) if !$ok;

}

sub _compare_lnpnumber {

    my ($got,$expected,$label) = @_;

    my $ok = 1;

    if ($expected->{id}) {
        $ok = is($got->{id},$expected->{id},$label . "check lnpnumber " . $got->{id} . " id") && $ok;
    }

    if ($expected->{start}) {
        $ok = is($got->{start},$expected->{start},$label . "check lnpnumber " . $got->{id} . " start date") && $ok;
    }

    if ($expected->{end}) {
        $ok = is($got->{end},$expected->{end},$label . "check lnpnumber " . $got->{id} . " end date") && $ok;
    }

    if ($expected->{number}) {
        $ok = is($got->{number},$expected->{number},$label . "check lnpnumber " . $got->{id} . " number") && $ok;
    }

    if ($expected->{carrier_id}) {
        $ok = is($got->{carrier_id},$expected->{carrier_id},$label . "check lnpnumber " . $got->{id} . " lnp_provider_id") && $ok;
    }

    return $ok;

}

sub _req_to_debug {
    my $request = shift;
    return { request => $request->method . " " . $request->uri,
            headers => $request->headers };
}

done_testing;
