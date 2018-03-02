use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Clone qw/clone/;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'numbers',
);
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
    ];
    $subscriber2->{content}->{alias_numbers} = [
        { cc=> '211', ac => $ticket, sn => $time },
        { cc=> '212', ac => $ticket, sn => $time },
        { cc=> '213', ac => $ticket, sn => $time },
    ];
    my ($res,$content,$request);
    ($res,$content,$request) = $subscriber_test_machine->request_put(@{$subscriber1}{qw/content location/});
    ($res,$content,$request) = $subscriber_test_machine->request_put(@{$subscriber2}{qw/content location/});
    my ($alias1) = $test_machine->get_item_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$subscriber1->{content}->{id});
    my ($alias2) = $test_machine->get_item_hal('numbers','/api/numbers/?type=alias&subscriber_id='.$subscriber2->{content}->{id});

    test_numbers_reassign($alias1,$alias2,$subscriber1,$subscriber2);

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

    test_numbers_reassign($alias1,$alias2,$subscriber1,$subscriber2);

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
    $alias1->{content}->{subscriber_id} = $subscriber2->{content}->{id};
    ($res) = $test_machine->request_patch([ { op => 'replace', path => '/subscriber_id', value => $subscriber2->{content}->{id} } ] , $alias1->{location});
    $test_machine->http_code_msg(200, "PATCH for /numbers/", $res);

    ($res) = $test_machine->request_patch([ { op => 'replace', path => '/subscriber_id', value => $subscriber1->{content}->{id} } ] , $alias1->{location});
    $test_machine->http_code_msg(200, "PATCH for /numbers/", $res);

    ($res) = $test_machine->request_patch([ { op => 'replace', path => '/subscriber_id', value => $subscriber1->{content}->{id} } ] , $alias2->{location});
    $test_machine->http_code_msg(200, "PATCH for /numbers/", $res);

    ($res) = $test_machine->request_patch([ { op => 'replace', path => '/subscriber_id', value => $subscriber2->{content}->{id} } ] , $alias2->{location});
    $test_machine->http_code_msg(200, "PATCH for /numbers/", $res);
}

# vim: set tabstop=4 expandtab:
