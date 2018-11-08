use strict;
use warnings;


use Test::More;
use Data::Dumper;


use Test::Collection;
use Test::FakeData;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'pbxdevices',
    embedded_resources => [qw/pbxdeviceprofiles customers/],
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    'pbxdevices' => {
        'data' => {
            profile_id   => sub { return shift->get_id('pbxdeviceprofiles',@_); },
            customer_id  => sub { return shift->get_id('customers',@_); },
            identifier   => 'aaaabbbbcccc',
            station_name => 'api_test_run',
            lines=>[{
                linerange      => 'Phone Ports api_test',
                type           => 'private',
                key_num        => '0',
                subscriber_id  => sub { return shift->get_id('subscribers',@_); },
                extension_unit => '1',
                extension_num  => '1',#to handle some the same extensions devices
                },{
                linerange      => 'Extra Ports api_test',
                type           => 'blf',
                key_num        => '1',
                subscriber_id  => sub { return shift->get_id('subscribers',@_); },
                extension_unit => '2',
            }],
        },
        'query' => ['station_name'],
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('pbxdevices'));


$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ use bignum qw/hex/; $_[0]->{identifier} = sprintf('%x', (hex('0x'.$_[0]->{identifier}) + $_[1]->{i}) ); no bignum;} );
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();


done_testing;

# vim: set tabstop=4 expandtab:
