use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'trustedsources',
    embedded_resources => [qw/subscribers/],
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    trustedsources => {
        data => {
            subscriber_id => sub { return shift->get_id('subscribers',@_); },
            protocol => 'UDP',
            src_ip => '203.0.113.42',
            from_pattern => '^sip:test@example.org',
        },
        query => ['subscriber_id'],
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('trustedsources'));

$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{src_ip} = sprintf('203.0.113.%d', $_[1]->{i}); } );
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
