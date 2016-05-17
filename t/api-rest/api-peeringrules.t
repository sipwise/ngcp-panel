use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'peeringrules',
    embedded_resources => [qw/peeringgroups/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    peeringrules => {
        data => {
            group_id  =>  sub { return shift->get_id('peeringgroups',@_); },
            callee_prefix  => '333',
            callee_pattern => '^111$',
            caller_pattern => '^222$',
            description    => 'api_test peering rule',
            enabled   => '1',
        }
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('peeringrules'));

$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{callee_prefix} .=  $_[1]->{i}; } );
{
    my $data = $test_machine->DATA_ITEM;
    $data->{callee_prefix} .= 1;
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(422, "POST same peering rule code again", $res, $result_item);
}
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;

# vim: set tabstop=4 expandtab:
