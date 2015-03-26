#use Sipwise::Base;
use strict;
#use Moose;
use Sipwise::Base;
use NGCP::Panel::Utils::Test::Collection;
use NGCP::Panel::Utils::Test::FakeData;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Test::More;
use Data::Dumper;
use File::Basename;
use bignum qw/hex/;

#init test_machine
my $test_machine = NGCP::Panel::Utils::Test::Collection->new( 
    name => 'pbxdevices', 
    embedded => [qw/pbxdeviceprofiles customers/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};
my $fake_data =  NGCP::Panel::Utils::Test::FakeData->new;
#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('pbxdevices'));


$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{identifier} = sprintf('%x', (hex('0x'.$_[0]->{identifier}) + $_[1]->{i}) ); } );
$test_machine->check_get2put(  );
$test_machine->check_bundle();
$test_machine->clear_test_data_all();


done_testing;

# vim: set tabstop=4 expandtab:
