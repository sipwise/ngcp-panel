use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'rewriterules',
    embedded_resources => [qw/rewriterulesets/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    rewriterules => {
        data => {
            set_id  =>  sub { return shift->get_id('rewriterulesets',@_); },
            match_pattern   => '^111$',
            replace_pattern => '222',
            description     => 'test_api rewrite rule',
            direction       => 'in',#out
            field           => 'caller',#calee
            priority        => '1',
            enabled         => '1',
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('rewriterules'));

$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{description} .=  $_[1]->{i}; } );
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;
__DATA__

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
    like($err->{message}, qr/(Invalid|Validation failed).*'set_id'/, "check error message in body");

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
    like($err->{message}, qr/Required: 'set_id'|set_id.*required/, "check error message in body");



# vim: set tabstop=4 expandtab:
