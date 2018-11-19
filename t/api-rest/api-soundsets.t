use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'soundsets',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    soundsets => {
        data => {
            reseller_id      =>  sub { return shift->get_id('resellers',@_); },
            contract_id      =>  sub { return shift->get_id('customers',@_); },
            name             => 'api_test soundset name'.time(),
            description      => 'api_test soundset description',
            contract_default => '1',#0
            copy_from_default => '1',#0
            language => 'en',
            override => '1',#0
            loopplay => '1',#0
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('soundsets'));

$test_machine->form_data_item( );
# create 3 new sound sets from DATA_ITEM
$test_machine->check_create_correct( 1, sub{ $_[0]->{name} .=  $_[1]->{i}; } );
$test_machine->check_get2put();
#$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
