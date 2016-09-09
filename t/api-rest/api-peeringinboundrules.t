use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Clone 'clone';
use JSON qw/from_json to_json/;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'peeringinboundrules',
    embedded_resources => [qw/peeringgroups/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    peeringinboundrules => {
        data => {
            group_id  =>  sub { return shift->get_id('peeringgroups',@_); },
            field => 'ruri_uri',
            pattern => '^111$',
            reject_code => undef,
            reject_reason => undef,
            priority => 50,
            enabled   => 1,
        }
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('peeringinboundrules'));

$test_machine->form_data_item( );
# create 3 new rules from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{pattern} .=  $_[1]->{i}; $_[0]->{priority} += $_[1]->{i}; } );
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} .= 1;
    $data->{priority} = 51;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST same peering rule code again", $res, $result_item);
}
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} .= 20;
    $data->{reject_code} = 404;
    $data->{reject_reason} = undef;
    $data->{priority} = 60;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST with reject code but no reject reason", $res, $result_item);
}
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} .= 21;
    $data->{reject_code} = undef;
    $data->{reject_reason} = "some reason";
    $data->{priority} = 61;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST with reject reason but no reject code", $res, $result_item);
}
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} .= 22;
    $data->{reject_code} = 399;
    $data->{reject_reason} = "some reason";
    $data->{priority} = 62;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST with too small code", $res, $result_item);
}
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} .= 23;
    $data->{reject_code} = 701;
    $data->{reject_reason} = "some reason";
    $data->{priority} = 63;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST with too large code", $res, $result_item);
}
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} .= 24;
    $data->{reject_code} = 400;
    $data->{reject_reason} = "some reason";
    $data->{priority} = 64;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(201, "POST with valid code and reason", $res, $result_item);
}
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{group_id} = 99999;
    $data->{priority} = 65;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST with invalid group_id", $res, $result_item);
}
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} = "my_identical_prio";
    $data->{priority} = 99;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(201, "POST with specific priority", $res, $result_item);
    $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} = "my_identical_prio_1";
    $data->{priority} = 99;
    my ($res2,$result_item2,$req2) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST with identical priority", $res2, $result_item2);
}
{
    my $data = clone($test_machine->DATA_ITEM);
    $data->{pattern} = "my_move_attempt";
    $data->{priority} = 101;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(201, "POST for preparing priority move attempt", $res, $result_item);
    if(defined $res->header('Location')) {
        my $rule_id = $res->header('Location'); $rule_id =~ s/^.+\/(\d+)$/$1/;
        my $uri = $test_machine->get_uri($rule_id);
        my ($res2,$result_item2,$req2) = $test_machine->request_get($uri);
        $test_machine->http_code_msg(200, "GET to fetch rule for priority move attempt", $res2, $result_item2);
        my $newdata = from_json($res2->decoded_content);
        delete $newdata->{_links};
        $newdata->{priority} = 99;
        my ($res3,$result_item3,$req3) = $test_machine->request_put($newdata, $uri);
        $test_machine->http_code_msg(422, "PUT to existing priority", $res3, $result_item3);
        $newdata->{priority} = 102;
        my ($res4,$result_item4,$req4) = $test_machine->request_put($newdata, $uri);
        $test_machine->http_code_msg(200, "PUT to new priority", $res4, $result_item4);
        $newdata->{reject_code} = undef;
        $newdata->{reject_reason} = "some reason";
        ($res4,$result_item4,$req4) = $test_machine->request_put($newdata, $uri);
        $test_machine->http_code_msg(422, "PUT with reason but without code", $res4, $result_item4);
        $newdata->{reject_code} = 401;
        $newdata->{reject_reason} = undef;
        ($res4,$result_item4,$req4) = $test_machine->request_put($newdata, $uri);
        $test_machine->http_code_msg(422, "PUT with code but without reason", $res4, $result_item4);
        $newdata->{reject_code} = 301;
        $newdata->{reject_reason} = "some reason";
        ($res4,$result_item4,$req4) = $test_machine->request_put($newdata, $uri);
        $test_machine->http_code_msg(422, "PUT with too small code", $res4, $result_item4);
        $newdata->{reject_code} = 700;
        $newdata->{reject_reason} = "some reason";
        ($res4,$result_item4,$req4) = $test_machine->request_put($newdata, $uri);
        $test_machine->http_code_msg(422, "PUT with too large code", $res4, $result_item4);
        $newdata->{reject_code} = 404;
        $newdata->{reject_reason} = "some reason";
        ($res4,$result_item4,$req4) = $test_machine->request_put($newdata, $uri);
        $test_machine->http_code_msg(200, "PUT with valid code and reason", $res4, $result_item4);
    }
}


$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
