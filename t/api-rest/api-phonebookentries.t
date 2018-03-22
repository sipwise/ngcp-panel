use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Clone qw/clone/;
use feature 'state';
#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'phonebookentries',
    QUIET_DELETION => 1,
);
my $subscriber_test_machine = Test::Collection->new(
    name => 'subscribers',
    QUIET_DELETION => 1,
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'phonebookentries' => {
        'data' => {
            contract_id          => sub { return shift->get_id('contracts',@_); },
            reseller_id          => sub { return shift->get_id('resellers',@_); },
            subscriber_id        => sub { return shift->get_id('subscribers',@_); },
            name                 => 'api_test phonebook username',
            number               => '111222333',
            shared               => '1',
        },
    },
});

$subscriber_test_machine->DATA_ITEM_STORE($fake_data->process('subscribers'));
$subscriber_test_machine->form_data_item();
$test_machine->DATA_ITEM_STORE($fake_data->process('phonebookentries'));
$test_machine->form_data_item();

my $remote_config = $test_machine->init_catalyst_config;

{#TT#34021
    my $subscriberadmin = $subscriber_test_machine->create()->[0];
    $test_machine->set_subscriber_credentials($subscriberadmin->{content});
    $test_machine->runas('subscriber');
    my $subscriber = $test_machine->check_create_correct(1, sub {
        my $num = $_[1]->{i};
        $_[0]->{webusername} .= time().'_34021_1';
        $_[0]->{webpassword} = 'api_test_webpassword';
        $_[0]->{username} .= time().'_34021_1' ;
        $_[0]->{pbx_extension} .= '340211';
        $_[0]->{primary_number}->{ac} .= '34021';
        $_[0]->{is_pbx_group} = 0;
        $_[0]->{is_pbx_pilot} = 0;
        delete $_[0]->{alias_numbers};
    } )->[0];
    if ($remote_config->{config}->{acl}->{subscriberadmin}->{subscribers} =~/write/) {
        $test_machine->check_get2put($subscriber,{},$put2get_check_params);
        my($res,$content,$req) = $test_machine->request_patch(  [ { op => 'replace', path => '/display_name', value => 'patched 34021' } ], $subscriber->{location} );
        $test_machine->http_code_msg(200, "Check display_name patch for subscriberadmin", $res, $content);
    }else{
        my($res,$content,$req) = $test_machine->request_patch(  [ { op => 'replace', path => '/display_name', value => 'patched 34021' } ], $subscriber->{location} );
        $test_machine->http_code_msg(403, "Check display_name patch for subscriberadmin", $res, $content, "Read-only resource for authenticated role");
    }
}

$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
$fake_data->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;


# vim: set tabstop=4 expandtab:
