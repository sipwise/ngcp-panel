#use Sipwise::Base;
use strict;

#use Moose;
use Sipwise::Base;
use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

use NGCP::Panel::Utils::DateTime;


#init test_machine
my $test_machine = Test::Collection->new(
    name => 'subscriberregistrations',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $expires = NGCP::Panel::Utils::DateTime::current_local();

$fake_data->set_data_from_script({
    'subscriberregistrations' => {
        data => {
           'contact' => 'test',
           'expires' => $expires->ymd('-') . ' ' . $expires->hms(':'),
           'subscriber_id' => sub { return shift->get_id('subscribers', @_); },
        },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('subscriberregistrations'));
$test_machine->form_data_item( );

# create 3 new vouchers from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{contact} .= time().'_'.$_[1]->{i} ; } );

#order of [check_bundle, check_get2put ] is important here: 
#subscriberregistrations really is just a wrapper arounf kamailio rpc calls, 
#and update of the existing item is made as delete+create. So, on every PUT or PATCH we delete item, and create new. 
#It makes internal Collection list of created items misordered with real data in db, 
#because Collection just keeps all created item, and doesn't try to recreate them on every update
$test_machine->check_bundle();
$test_machine->check_get2put();


#$test_machine->clear_test_data_all();


done_testing;

# vim: set tabstop=4 expandtab:
