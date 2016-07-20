use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'reminders',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'reminders' => {
        'data' => {
            subscriber_id => sub { return shift->get_id('subscribers',@_); },
            recur         => 'weekdays',#never' (only once)|'weekdays' (on weekdays)|'always' (everyday)
            'time'        => '14:00',
        },
        'query' => ['subscriber_id'],
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('reminders'));
$test_machine->form_data_item();
$test_machine->check_create_correct( 1,  );
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
done_testing;


# vim: set tabstop=4 expandtab:
