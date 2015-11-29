use strict;
use warnings;

use Test::More;
use Test::Collection;
use Test::FakeData;
use Data::Dumper;

my $test_machine = Test::Collection->new(
    name => 'callforwards',
);


$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'callforwards' => {
        'data' => {
            #not really necessary - there isn't POST method
            #subscriber_id  => sub { return shift->get_id('subscribers',@_); },
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
        },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('callforwards'));
$test_machine->form_data_item( );

SKIP:{
    my ($res,$req);
    my $cf1 = $test_machine->get_item_hal();
    
    if(!$cf1->{content}->{total_count}){
        skip("Testing requires at least one present callforward. No creation is available.",1);
    }

    #$test_machine->check_bundle();

    my($cf1_id) = $test_machine->get_id_from_hal($cf1->{content}); #($cf1,'callforwards');
    cmp_ok ($cf1_id, '>', 0, "should be positive integer");
    my $cf1single_uri = "/api/callforwards/$cf1_id";
    my $cf1single;
    (undef, $cf1single) = $test_machine->check_item_get($cf1single_uri,"fetch cf id $cf1_id");

    is(ref $cf1single, "HASH", "cf should be hash");
    ok(exists $cf1single->{cfu}, "cf should have key cfu");
    ok(exists $cf1single->{cfb}, "cf should have key cfb");
    ok(exists $cf1single->{cft}, "cf should have key cft");
    ok(exists $cf1single->{cfna}, "cf should have key cfna");

    $test_machine->check_put2get({data_in => $test_machine->DATA_ITEM, uri => $cf1single_uri});
    #($res, $rescontent, $req) = $test_machine->request_put( $test_machine->DATA_ITEM, $cf1single_uri );
}

done_testing;

1;


__DATA__


{

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
    is ($cf1put->{cft}{destinations}->[0]->{simple_destination}, "5678", "Check first destination of cft");
    like ($cf1put->{cft}{destinations}->[0]->{destination}, qr/^sip:5678@/, "Check first destination of cft (regex, full uri)");
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
