use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'cftimesets',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'cftimesets' => {
        'data' => {
            name        => 'API_test call forward time-set',
            subscriber_id => sub { return shift->get_id('subscribers',@_); },
            times     => [{
                wday     => '1-5',
                hour     => '5-5',
                minute   => '50-59',
                year     => undef,
                month    => undef,
                mday     => undef,
            },],
        },
        'query' => ['name'],
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('cftimesets'));
$test_machine->form_data_item();
$test_machine->check_create_correct( 1 );
$test_machine->check_get2put();
$test_machine->check_bundle();
{
#test cyclic wday input
    diag("Cyclic wday input;\n\n");
    $test_machine->check_create_correct(1,sub{
        $_[0]->{wday} = '6-1';
    });
}

$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
undef $fake_data;
undef $test_machine;
done_testing;


# vim: set tabstop=4 expandtab:
