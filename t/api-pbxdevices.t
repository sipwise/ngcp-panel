#use Sipwise::Base;
use strict;

#use Moose;
use Sipwise::Base;
use lib "/root/VMHost/ngcp-panel/t/lib/";
extends 'Test::Collection';
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Test::More;
use Data::Dumper;
use File::Basename;
use bignum qw/hex/;

#init test_machine
my $test_machine = Test::Collection->new( 
    name => 'pbxdevices', 
    embedded => [qw/pbxdeviceprofiles customers/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};
#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE({
    'profile_id' => '151',
    #somehow should obtain/create test customer with the test subscriber - discuss with alex
    #'customer_id' => '968',
    'identifier' => 'aaaabbbbcccc',
    'station_name' => 'abc',
    'lines'=>[{
        'linerange' => 'Phone Ports',
        'type' => 'private',
        'key_num' => '0',
    #somehow should obtain/create test customer with the test subscriber - discuss with alex
#'subscriber_id' => '1198',
        'extension_unit' => '1',
        #'extension_num' => '1',#to handle some the same extensions devices
        },{
        'linerange' => 'Phone Ports',
        'type' => 'private',
        'key_num' => '1',
    #somehow should obtain/create test customer with the test subscriber - discuss with alex
        #'subscriber_id' => '1198',
        'extension_unit' => '2',
    }],
});


$test_machine->form_data_item( );
# create 6 new billing models from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{identifier} = sprintf('%x', (hex('0x'.$_[0]->{identifier}) + $_[1]->{i}) ); } );
$test_machine->check_get2put(  );
$test_machine->check_bundle();
$test_machine->check_delete_use_created();


done_testing;

# vim: set tabstop=4 expandtab:
