use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'faxserversettings',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET OPTIONS HEAD)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET OPTIONS HEAD PUT PATCH)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    faxserversettings => {
        data => {
            'name'            => 'api_test_'.time(),
            'password'        => 'api_test_password',
            'active'          => '1',#0|1,
            't38'             => '1',#0|1,
            'ecm'             => '1',#0|1,
            'destinations'   => [{
                'destination'     => 'some@email.com',
                'filetype'        => 'TIFF',#TIFF,PS,PDF,PDF14
                'incoming'        => '1',#0|1
                'outgoing'        => '1',#0|1
                'status'          => '1',#0|1
            }],
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('faxserversettings'));

$test_machine->form_data_item( );
$test_machine->check_bundle();
$test_machine->check_get2put();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
