use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'timesets',
    DEBUG => 1,
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    timesets => {
        data => {
            reseller_id       =>  sub { return shift->get_id('resellers',@_); },
            name              => 'api_test_timeset_name',
            times             => [{
                start         => '1971-01-01 00:00:01',
                end           => '2020-12-31 23:59:59',
                freq          => 'daily',
                interval      => '5',
                until         => '2021-01-01 23:59:59',
                #count         => '3', #or until or count
                bysecond      => '1,3,5',
                byminute      => '3,5,7',
                byhour        => '5,7,9',
                byday         => '5,-7,9',#it is byweekday
                bymonthday    => '-5,7,-9',
                bymonth       => '1,2,6',
                byyearday     => '-200,200,-100,100',
                bysetpos      => '-200,200,-100,100',
                byweekno      => '1,2,3',
            }],
        },
        'query' => ['name'],
        'data_callbacks' => {
            'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('timesets'));

$test_machine->form_data_item( );
# create 3 new sound sets from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{name} .=  $_[1]->{i}; } );
my $headers_old = $test_machine->set('HEADERS' => {'GET' => {'Accept' => 'application/json'}});
$test_machine->check_get2put();
$test_machine->set('HEADERS' => $headers_old);
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
