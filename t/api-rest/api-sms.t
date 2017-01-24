use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'sms',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    'sms' => {
        'data' => {
            subscriber_id  => sub { return shift->get_id('subscribers',@_); },
            coding         => 0,
            direction      => 'out',
            caller         => '111111111',
            callee         => '+111111111',
            text           => 'Some text',
        },
        'no_delete_available' => 1,
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('sms'));
$test_machine->form_data_item( );

my $sms = $test_machine->check_create_correct(1)->[0];
$test_machine->check_bundle();
$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();
undef $fake_data;
undef $test_machine;

done_testing;

# vim: set tabstop=4 expandtab:
