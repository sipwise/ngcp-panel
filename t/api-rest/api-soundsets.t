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
my $soundsets_with_files = $test_machine->check_create_correct( 1, sub{ $_[0]->{name} .=  $_[1]->{i}; } );
my $soundsets_without_contract = $test_machine->check_create_correct( 1, sub{ delete $_[0]->{contract_id}; } );
my $soundsets_without_files = $test_machine->check_create_correct( 1, sub{ 
    $_[0]->{name} .=  $_[1]->{i}; 
    $_[0]->{copy_from_default} =  0; 
} );
my($res,$content,$req) = $test_machine->request_put({
    %{$test_machine->DATA_ITEM},
    copy_from_default => '1',#0
    language => 'en',
    override => '1',#0
    loopplay => '1',#0
},$soundsets_with_files->[0]->{location} );
$test_machine->http_code_msg(200, "Check put with files replacement", $res, $content);
$test_machine->check_get2put();
$test_machine->check_bundle();
#$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
