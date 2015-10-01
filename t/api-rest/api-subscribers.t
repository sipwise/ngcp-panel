#use Sipwise::Base;
use strict;

#use Moose;
use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

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

# create 3 new subscribers from DATA_ITEM

##$test_machine->check_create_correct( 3, sub{ $_[0]->{username} .= time().'_'.$_[1]->{i} ; } );
##$test_machine->check_bundle();
##$test_machine->check_get2put();

#-------  MT#15441
{  
    my($res,$preferences,$preferences2,$preferences_from_put,$subscriber_from_put,$subscriber2);
    # || $test_machine->get_created_first()
    my $subscriber = $fake_data->get_existent_item($test_machine->name) || $test_machine->get_item_hal();    
    my $subscriber_id = $test_machine->get_id_from_created($subscriber);
    my $preferences_uri = '/api/subscriberpreferences/'.$subscriber_id;
    ($res, $preferences) = $test_machine->check_item_get($preferences_uri);
    my $intentional_cli = '111'.time();
    $preferences->{cli} = $intentional_cli;
    ($res, $preferences_from_put) = $test_machine->request_put($preferences,$preferences_uri);
    is($preferences_from_put->{cli}, $intentional_cli, "check that cli was updated on subscriberpreferences put: $preferences_from_put->{cli} == $intentional_cli");
    my $intentional_primary_number = {
        'cc' => '111',
        'ac' => '222',
        'sn' => '123'.time(),
    };
    $subscriber->{content}->{primary_number} = $intentional_primary_number;
    ($res, $subscriber_from_put) = $test_machine->request_put($subscriber->{content},$subscriber->{location});
    ($res, $subscriber2) = $test_machine->check_item_get($subscriber->{location});
    is_deeply($subscriber2->{primary_number}, $intentional_primary_number, "check that primary_number was updated on subscribes put");
    ($res, $preferences2) = $test_machine->check_item_get($preferences_uri);
    is($preferences2->{cli}, $intentional_cli, "check that cli was preserved on subscriber phones update: $preferences2->{cli} == $intentional_cli");
}

$test_machine->clear_test_data_all();
done_testing;

# vim: set tabstop=4 expandtab:
