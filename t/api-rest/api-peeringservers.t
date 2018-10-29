use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'peeringservers',
    embedded_resources => [qw/peeringgroups/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    peeringservers => {
        data => {
            group_id  =>  sub { return shift->get_id('peeringgroups',@_); },
            name      => 'test_api peering host',
            ip        => '1.1.1.1',
            host      => 'test-api.com',
            port      => '1025',
            transport => '1',
            weight    => '1',
            via_route => '',
            via_lb    => '',
            enabled   => '1',
        },
        query => ['name'],
        'data_callbacks' => {
            'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('peeringservers'));

$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{name} .=  $_[1]->{i}; } );
{
    my $data = $test_machine->DATA_ITEM;
    $data->{name} .= 1;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST same peering server name again", $res, $result_item);
}
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

undef $test_machine;
undef $fake_data;
done_testing;
# vim: set tabstop=4 expandtab:
