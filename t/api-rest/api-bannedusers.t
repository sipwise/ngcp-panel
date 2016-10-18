use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'bannedusers',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS DELETE)};

$fake_data->set_data_from_script({
    'bannedusers' => {
        'data' => {
        },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('bannedusers'));
$test_machine->ALLOW_EMPTY_COLLECTION(1);
$test_machine->form_data_item();

my $hal_before = $test_machine->get_item_hal(undef,undef,1);

my $time = time();
my @users = qw/user1 user2 user3/;
foreach (@users){
    my $cmd1 = "ngcp-sercmd lb htable.sets auth $_\@domain.com::auth_count 10";
    my $cmd2 = "ngcp-sercmd lb htable.sets auth $_\@domain.com::last_auth $time";
    print $cmd1."\n".$cmd2."\n";
    `$cmd1`;
    `$cmd2`;
}

$test_machine->check_bundle();
if(!$test_machine->IS_EMPTY_COLLECTION){
    $test_machine->clear_test_data_all([map {"/api/bannedusers/$_\@domain.com"} @users]);
}
if(!$hal_before || $hal_before->{content_collection}->{total_count} < 1){
    my $hal_after = $test_machine->get_item_hal(undef,undef,1);
    print Dumper $hal_after;
    is($hal_after, undef, "Check that all added banned users were deleted");
}
done_testing;


# vim: set tabstop=4 expandtab:
