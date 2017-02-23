use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'domains',
    QUIET_DELETION => 0,
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    'domains' => {
        'data' => {
            domain => 'api_test.api_test',
            reseller_id => sub { return shift->get_id('resellers',@_); },
        },
        'query' => ['domain'],
        'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{domain}); },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('domains'));

$test_machine->form_data_item( );
# create 3 new sound sets from DATA_ITEM
$test_machine->check_create_correct( 1, sub{ $_[0]->{domain} .=  $_[1]->{i}.time(); } );
$test_machine->check_bundle();

$test_machine->runas('reseller');
diag('8185: Run as reseller');
$test_machine->check_create_correct( 1, sub{ $_[0]->{domain} .=  'reseller'.$_[1]->{i}.time(); } );
$test_machine->check_bundle();



$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
