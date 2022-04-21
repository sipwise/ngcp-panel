use strict;
use warnings;

use threads;
use Test::Collection;
use Test::FakeData;
use JSON;
use Test::More;
use Data::Dumper;
use Clone qw/clone/;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'numbers',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH)};


my $fake_data = Test::FakeData->new;

$fake_data->set_data_from_script({
    'numbers' => {
        'data' => {
            subscriber_id  => sub { return shift->get_id('subscribers',@_); },
            cc => 1,
            ac => 1,
            sn => 1,
        },
    },
});

my $fake_data_processed = $fake_data->process('numbers');
$test_machine->DATA_ITEM_STORE($fake_data_processed);
$test_machine->form_data_item();

my ($res,$content,$req);

my $subscriber = $test_machine->get_item_hal('subscribers', '/api/subscribers/'.$test_machine->DATA_ITEM->{subscriber_id}, 1);

#  cc WILL loose leading zero, as far as column billing.voip_numbers.cc is a integer and truncates leading zero
my $number_aliases_data = [
    {'cc' => '11', 'ac' => '0022', 'sn' => '00444'.time().seq(),},
    {'cc' => '11', 'ac' => '0022', 'sn' => '00444'.time().seq(),},
    {'cc' => '11', 'ac' => '0022', 'sn' => '00444'.time().seq(),},
];

($res,$content,$req) = $test_machine->request_patch( [ {
    op => 'replace',
    path => '/alias_numbers',
    value => $number_aliases_data
} ], $subscriber->{location} );
$test_machine->http_code_msg(200, "Check patch alias_numbers", $res, $content);

my $number_aliases = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$test_machine->DATA_ITEM->{subscriber_id}, 1)->{collection};
my $number_primary = $test_machine->get_item_hal('numbers', '/api/numbers/?type=primary&subscriber_id='.$test_machine->DATA_ITEM->{subscriber_id}, 1);

#check that we didn't loose leading zeros
my $number_aliases_got = [ map {{'ac' => $_->{content}->{ac}, 'cc' =>  $_->{content}->{cc}, 'sn' => $_->{content}->{sn}}} @$number_aliases];
is_deeply($number_aliases_got, $number_aliases_data,"check that we didn't loose leading zeros in ac, cc, sn");

$test_machine->check_bundle();
$test_machine->check_get2put(  {location => $number_aliases->[0]->{location}});
$test_machine->check_patch2get({location => $number_aliases->[0]->{location}});

$test_machine->check_patch2get({
        location => $number_aliases->[0]->{location},
        content => [
            {'op' => 'replace', 'path' => '/is_devid', 'value' => JSON::true },
        ],
    });

#Two tests below will fail with error: Unprocessable Entity: Cannot reassign primary number, already at subscriber 357
#$test_machine->check_get2put(  {location => $number_primary->{location}});
#$test_machine->check_patch2get({location => $number_primary->{location}}, undef, {
##we can exclude subscriber_id from patch, but anyway old_resource will provide it
#   patch_exclude_fields => ['subscriber_id'],
#});

{
    my $ticket = '32913';
    my $time = time();
    my $subscriber_test_machine = Test::Collection->new(
        name => 'subscribers',
    );
    $subscriber_test_machine->DATA_ITEM_STORE($fake_data->process('subscribers'));
    my $subscriber1 = $fake_data->create('subscribers')->[0];
    my $subscriber2 = $fake_data->create('subscribers')->[0];
    #print Dumper $subscriber1;
    $subscriber1->{content}->{alias_numbers} = [
        { cc=> '111', ac => $ticket, sn => $time },
        { cc=> '112', ac => $ticket, sn => $time },
        { cc=> '113', ac => $ticket, sn => $time },
#        { cc=> '114', ac => $ticket, sn => $time },
#        { cc=> '115', ac => $ticket, sn => $time },
    ];
    $subscriber2->{content}->{alias_numbers} = [
        { cc=> '211', ac => $ticket, sn => $time },
        { cc=> '212', ac => $ticket, sn => $time },
        { cc=> '213', ac => $ticket, sn => $time },
#        { cc=> '214', ac => $ticket, sn => $time },
#        { cc=> '215', ac => $ticket, sn => $time },
    ];
    my ($res,$content,$request);
    ($res,$content,$request) = $subscriber_test_machine->request_put(@{$subscriber1}{qw/content location/});
    ($res,$content,$request) = $subscriber_test_machine->request_put(@{$subscriber2}{qw/content location/});
    my ($aliases1) = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$subscriber1->{content}->{id}, 1)->{collection};
    my ($aliases2) = $test_machine->get_collection_hal('numbers','/api/numbers/?type=alias&subscriber_id='.$subscriber2->{content}->{id}, 1)->{collection};
    test_numbers_reassign($aliases1->[0],$aliases2->[0],$subscriber1,$subscriber2);

    my $pbxsubscriberadmin = $fake_data->create('subscribers')->[0];
    ($res) = $subscriber_test_machine->request_patch([
        { op => 'replace', path => '/administrative', value => 1 },
        { op => 'replace', path => '/webpassword', value => 'pbxadminpwd' },
        { op => 'replace', path => '/password', value => 'pbxadminpwd' }
    ] , $pbxsubscriberadmin->{location});
    $subscriber_test_machine->http_code_msg(200, "PATCH for /pbxsubscriberadmin/", $res);
    $pbxsubscriberadmin = $subscriber_test_machine->get_item_hal('subscribers', $pbxsubscriberadmin->{location});

    $test_machine->set_subscriber_credentials($pbxsubscriberadmin->{content});
    $test_machine->runas('subscriber');

    test_numbers_reassign($aliases1->[0],$aliases2->[0],$subscriber1,$subscriber2);
    my @threads;
    for(my $i = 0; $i < @{$aliases1} && $i < @{$aliases2}; $i++ ){
        push @threads, threads->create(\&test_numbers_reassign,$aliases1->[$i],$aliases2->[$i],$subscriber1,$subscriber2);
    }
    for(my $i=0; $i < @threads; $i++ ){
        $threads[$i]->join();
    }
    $test_machine->runas('admin');

    $subscriber_test_machine->clear_test_data_all();#fake data aren't registered in this test
}

$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
$fake_data->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;

sub test_numbers_reassign{
    my($alias1,$alias2,$subscriber1,$subscriber2) = @_;
    my $res;
    my $test_machine_l = Test::Collection->new(
        name => 'numbers',
    );

    #print Dumper [
    #    [ { op => 'replace', path => '/subscriber_id', value => $subscriber2->{content}->{id} } ] , $alias1,
    #    [ { op => 'replace', path => '/subscriber_id', value => $subscriber1->{content}->{id} } ] , $alias1,
    #    [ { op => 'replace', path => '/subscriber_id', value => $subscriber1->{content}->{id} } ] , $alias2,
    #    [ { op => 'replace', path => '/subscriber_id', value => $subscriber2->{content}->{id} } ] , $alias2
    #
    #];
    my $tid = threads->tid();
    $alias1->{content}->{subscriber_id} = $subscriber2->{content}->{id};
    ($res) = $test_machine_l->request_patch([ { op => 'replace', path => '/subscriber_id', value => $subscriber2->{content}->{id} } ] , $alias1->{location});
    $test_machine_l->http_code_msg(200, "PATCH 1 for /numbers/ in tid $tid;", $res);

    ($res) = $test_machine_l->request_patch([ { op => 'replace', path => '/subscriber_id', value => $subscriber1->{content}->{id} } ] , $alias1->{location});
    $test_machine_l->http_code_msg(200, "PATCH 2 for /numbers/ in tid $tid;", $res);

    ($res) = $test_machine_l->request_patch([ { op => 'replace', path => '/subscriber_id', value => $subscriber1->{content}->{id} } ] , $alias2->{location});
    $test_machine_l->http_code_msg(200, "PATCH 3 for /numbers/ in tid $tid;", $res);

    ($res) = $test_machine_l->request_patch([ { op => 'replace', path => '/subscriber_id', value => $subscriber2->{content}->{id} } ] , $alias2->{location});
    $test_machine_l->http_code_msg(200, "PATCH 4 for /numbers/ in tid $tid;", $res);
}

# vim: set tabstop=4 expandtab:
