use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'bannedips',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS DELETE)};

$fake_data->set_data_from_script({
    'bannedips' => {
        'data' => {
        },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('bannedips'));
$test_machine->ALLOW_EMPTY_COLLECTION(1);
$test_machine->form_data_item();

my $time = time();

my $hal_before = $test_machine->get_item_hal(undef,undef,1);

my @ips = qw/127.0.0.1 127.0.0.2 127.0.0.3/;
foreach (@ips){
    `ngcp-sercmd lb htable.sets ipban $_ 1`;
}

$test_machine->check_bundle();

if(!$test_machine->IS_EMPTY_COLLECTION){
    $test_machine->clear_test_data_all([map {"/api/bannedips/$_"} @ips]);
}
if(!$hal_before || $hal_before->{content_collection}->{total_count} < 1){
    my $hal_after = $test_machine->get_item_hal(undef,undef,1);
    is($hal_after, undef, "Check that all added banned ips were deleted");
}
#fake data aren't registered in this test machine, so they will stay.
done_testing;


# vim: set tabstop=4 expandtab:
