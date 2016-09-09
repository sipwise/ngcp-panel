use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

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
$test_machine->check_create_correct( 3, sub{ $_[0]->{pattern} .=  $_[1]->{i}; } );
{
    my $data = $test_machine->DATA_ITEM;
    $data->{pattern} .= 1;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST same peering rule code again", $res, $result_item);
}
{
    my $data = $test_machine->DATA_ITEM;
    $data->{pattern} .= 2;
    $data->{reject_code} = 404;
    $data->{reject_reason} = undef;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST with reject code but no reject reason", $res, $result_item);
}
{
    my $data = $test_machine->DATA_ITEM;
    $data->{pattern} .= 3;
    $data->{reject_code} = undef;
    $data->{reject_reason} = "some reason";
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST with reject reason but no reject code", $res, $result_item);
}
{
    my $data = $test_machine->DATA_ITEM;
    $data->{pattern} .= 4;
    $data->{reject_code} = 404;
    $data->{reject_reason} = "some reason";
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(201, "POST with reject code and reject reason", $res, $result_item);
}
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
