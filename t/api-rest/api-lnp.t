use Sipwise::Base;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use JSON qw();
use Test::More;

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

{ #regular case
    my $carrier1 = _create_lnp_provider();
    my $number1 = _create_lnp_number($carrier1, number => '123');
    my $number2 = _create_lnp_number($carrier1, number => '456');
    _delete_lnp_number($number1);
    _delete_lnp_number($number2);
    _delete_lnp_provider($carrier1);
}

{ #delete provider with numbers left:
    my $carrier1 = _create_lnp_provider();
    my $number1 = _create_lnp_number($carrier1, number => '123');
    _delete_lnp_provider($carrier1, 500);
}

{ #unique number - insert:
    my $carrier1 = _create_lnp_provider();
    my $number1 = _create_lnp_number($carrier1, number => '123');
    my $number2 = _create_lnp_number($carrier1, number => '123', expected_code => 422);
    #_delete_lnp_provider($carrier1, expected_code => 500);
}

{ #unique number - update:
    my $carrier1 = _create_lnp_provider();
    my $number1 = _create_lnp_number($carrier1, number => '123');
    my $number2 = _create_lnp_number($carrier1, number => '1234');
    _update_lnp_number($number2, number => '123', expected_code => 422);
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

done_testing;
