use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'emergencymappingcontainers',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'emergencymappingcontainers' => {
        data => {
            reseller_id => sub { return shift->get_id('resellers', @_); },
            name               => "apitest",
        },
        'query' => ['name','reseller_id'],
        'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('emergencymappingcontainers'));
$test_machine->form_data_item( );

# create 3 new billing zones from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{name} .= $_[1]->{i} ; } );
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();
done_testing;

# vim: set tabstop=4 expandtab:
