use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#use NGCP::Panel::Utils::Subscriber;

my $test_machine = Test::Collection->new(
    name => 'subscribers',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'subscribers' => {
        'data' => {
            administrative       => 0,
            customer_id          => sub { return shift->get_id('customers',@_); },
            primary_number       => { ac => 111, cc=> 111, sn => 111 },
            alias_numbers        => [ { ac => 11, cc=> 11, sn => 11 } ],
            username             => 'api_test_username',
            password             => 'api_test_password',
            webusername          => 'api_test_webusername',
            webpassword          => undef,
            domain_id            => sub { return shift->get_id('domains',@_); },,
            #domain_id            =>
            email                => undef,
            external_id          => undef,
            is_pbx_group         => 1,
            is_pbx_pilot         => 1,
            pbx_extension        => '111',
            pbx_group_ids        => [],
            pbx_groupmember_ids  => [],
            profile_id           => sub { return shift->get_id('subscriberprofiles',@_); },
            status               => 'active',
            pbx_hunt_policy      => 'parallel',
            pbx_hunt_timeout     => '15',
        },
        'query' => ['username'],
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('subscribers'));
$test_machine->form_data_item( );

# create new subscribers from DATA_ITEM. Item is not created in the fake_data->process.

$test_machine->check_create_correct( 1, sub{ $_[0]->{username} .= time().'_'.$_[1]->{i} ; } );
$test_machine->check_bundle();
$test_machine->check_get2put();
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
my $remote_config = $test_machine->init_catalyst_config;
#-------  MT#15441
{
    my $intentional_cli = '111'.time();
    my $intentional_primary_number = {
        'cc' => '111',
        'ac' => '222',
        'sn' => '123'.time(),
    };

    #prepare preconditions: cli should differ from primary_nuber
    #my $subscriber = ($test_machine->get_created_first() || $fake_data->get_existent_item($test_machine->name) || $test_machine->get_item_hal());
    my $subscriber = $test_machine->check_create_correct( 1, sub{
        my $num = $_[1]->{i};
        $_[0]->{username} .= time().'_'.$num ;
        $_[0]->{webusername} .= time().'_'.$num;
        $_[0]->{pbx_extension} .= $num;
        $_[0]->{primary_number}->{ac} .= $num;
        $_[0]->{is_pbx_group} = 0 ;
        $_[0]->{is_pbx_pilot} = 1 ;
    }
    )->[0];
    $subscriber->{uri} = $subscriber->{location};
    my ($preferences, $preferences_put) = ({'uri' => '/api/subscriberpreferences/'.$test_machine->get_id_from_created($subscriber)}) x 2;
    (undef, $preferences->{content}) = $test_machine->check_item_get($preferences->{uri});
    $preferences->{content}->{cli} = $intentional_cli;
    (undef, $preferences_put->{content}) = $test_machine->request_put($preferences->{content},$preferences->{uri});

    is($preferences_put->{content}->{cli}, $intentional_cli, "check that cli was updated on subscriberpreferences put: $preferences_put->{content}->{cli} == $intentional_cli");

    my ($subscriber_put, $subscriber_get, $preferences_get);

#1
    $subscriber->{content}->{primary_number} = $intentional_primary_number;
    ($subscriber_put,$subscriber_get,$preferences_get) = $test_machine->put_and_get($subscriber, $preferences_put);
    is($preferences_get->{content}->{cli}, $intentional_cli, "check that cli was preserved on subscriber phones update: $preferences_get->{content}->{cli} == $intentional_cli");
#/1
#2
    delete $subscriber->{content}->{primary_number};
    ($subscriber_put,$subscriber_get,$preferences_get) = $test_machine->put_and_get($subscriber, $preferences_put);
    is($preferences_get->{content}->{cli}, $intentional_cli, "check that cli was preserved on subscriber phones update: $preferences_get->{content}->{cli} == $intentional_cli");
#/2
    #now prepare preferences for zero situation, when synchronization will be restarted again
    delete $preferences->{content}->{cli};
    (undef, $preferences_put->{content}) = $test_machine->request_put($preferences->{content},$preferences->{uri});
    is($preferences_put->{content}->{cli}, undef, "check that cli was deleted on subscriberpreferences put with empty cli");
    if($remote_config->{config}->{numbermanagement}->{auto_sync_cli}){
    #3
        $subscriber->{content}->{primary_number} = $intentional_primary_number;
        ($subscriber_put,$subscriber_get,$preferences_get) = $test_machine->put_and_get($subscriber, $preferences_put);
        is($preferences_get->{content}->{cli}, number_as_string($intentional_primary_number), "check that cli was created on subscriber phones update: $preferences_get->{content}->{cli} == ".number_as_string($intentional_primary_number) );
    #/3
        $intentional_primary_number = {
            'cc' => '222',
            'ac' => '333',
            'sn' => '444'.time(),
        };
    #4
        $subscriber->{content}->{primary_number} = $intentional_primary_number;
        ($subscriber_put,$subscriber_get,$preferences_get) = $test_machine->put_and_get($subscriber, $preferences_put);
        is($preferences_get->{content}->{cli}, number_as_string($intentional_primary_number), "check that cli was updated on subscriber phones update: $preferences_get->{content}->{cli} == ".number_as_string($intentional_primary_number) );
    #/4
    #5
        delete $subscriber->{content}->{primary_number};
        ($subscriber_put,$subscriber_get,$preferences_get) = $test_machine->put_and_get($subscriber, $preferences_put);
        is($preferences_get->{content}->{cli}, undef, "check that cli was deleted on subscriber phones update");
    #/5
    }
    $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
}
{
#18601
    diag("18601");
    my $groups = $test_machine->check_create_correct( 3, sub{
        my $num = $_[1]->{i};
        $_[0]->{username} .= time().'_'.$num ;
        $_[0]->{webusername} .= time().'_'.$num;
        $_[0]->{pbx_extension} .= $num;
        $_[0]->{primary_number}->{ac} .= $num;
        $_[0]->{is_pbx_group} = 1 ;
        $_[0]->{is_pbx_pilot} = $_[1]->{i} > 1 ? 0 : 1; #  ;
        delete $_[0]->{alias_numbers};
    } );
    my $member_1 = $test_machine->check_create_correct( 1, sub{
        my $num = 3 + $_[1]->{i};
        $_[0]->{username} .= time().'_'.$num ;
        $_[0]->{webusername} .= time().'_'.$num;
        $_[0]->{pbx_extension} .= $num;
        $_[0]->{primary_number}->{ac} .= $num;
        $_[0]->{is_pbx_group} = 0 ;
        $_[0]->{is_pbx_pilot} = 0 ;
        delete $_[0]->{alias_numbers};
    }
    )->[0];
    $member_1->{uri} = $member_1->{location};
    $member_1->{content}->{pbx_group_ids} = [];
    my($member_put,$member_get) = $test_machine->check_put2get($member_1);
    $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
}
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
done_testing;


sub number_as_string{
    my ($number_row, %params) = @_;
    return 'HASH' eq ref $number_row
        ? $number_row->{cc} . ($number_row->{ac} // '') . $number_row->{sn}
        : $number_row->cc . ($number_row->ac // '') . $number_row->sn;
}

# vim: set tabstop=4 expandtab:
