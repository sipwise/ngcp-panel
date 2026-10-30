use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Clone qw/clone/;
use JSON ();
use List::Util qw/any/;
use feature 'state';
#use NGCP::Panel::Utils::Subscriber;
#use Data::Compare qw//;

my $test_machine = Test::Collection->new(
    name => 'subscribers',
    QUIET_DELETION => 1,
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'subscribers' => {
        'data' => {
            administrative       => 0,
            customer_id          => sub { return shift->get_id('customers',@_); },
            primary_number       => { ac => 12, cc=> 12, sn => 12 },
            alias_numbers        => [ { ac => 112, cc=> 112, sn => 112 } ],
            username             => 'api_test_username',
            password             => 'api_test_password',
            webusername          => 'api_test_webusername',
            webpassword          => 'web_password_1',
            domain_id            => sub { return shift->get_id('domains',@_); },
            #domain_id            =>
            email                => undef,
            external_id          => undef,
            is_pbx_group         => 1,
            is_pbx_pilot         => 1,
            #sub {
            #    my($self) = @_;
            #    my $pilot = $self->test_machine->get_item_hal('subscribers','/api/subscribers/?customer_id='.$self->data->{$collection_name}->{data}->{customer_id}.'&'.'is_pbx_pilot=1');
            #    if($pilot->{content}->{total_count} > 0){
            #        return 0;
            #    }
            #    return 1;
            #},
            pbx_extension        => '111',
            pbx_group_ids        => [],
            pbx_groupmember_ids  => [],
            profile_id           => sub { return shift->get_id('subscriberprofiles',@_); },
            profile_set_id       => sub { return shift->get_id('subscriberprofilesets',@_); },
            status               => 'active',
            pbx_hunt_policy      => 'parallel',
            pbx_hunt_timeout     => '15',
            pbx_hunt_cancel_mode     => 'cancel',
        },
        'query' => [['username',{'query_type'=> 'string_like'}]],
        'create_special'=> sub {
            state $num;
            $num //= 0;
            $num++;
            my ($self,$collection_name,$test_machine) = @_;
            my $pilot = $test_machine->get_item_hal('subscribers','/api/subscribers/?customer_id='.$self->data->{$collection_name}->{data}->{customer_id}.'&'.'is_pbx_pilot=1');
            if(!$pilot->{total_count} || $pilot->{total_count} <= 0){
                undef $pilot;
            }
            return $test_machine->check_create_correct(1, sub{
                my $time = time;
                $_[0]->{is_pbx_pilot} = ($pilot || $_[1]->{i} > 1)? 0 : 1;
                $_[0]->{pbx_extension} = $time.$num.Test::FakeData::seq;
                $_[0]->{webusername} .= $time.$num.Test::FakeData::seq;
                $_[0]->{username} .= $time.$num.Test::FakeData::seq;
                delete $_[0]->{alias_numbers};
                $_[0]->{primary_number}->{sn} = $time.$num;
            }, $self->data->{$collection_name}->{data} );
        },
        'update_change_fields' => [qw/modify_timestamp create_timestamp primary_number_id webpassword/],
    },
});

my $fake_data_processed = $fake_data->process('subscribers');
my $pilot = $test_machine->get_item_hal('subscribers','/api/subscribers/?customer_id='.$fake_data_processed->{customer_id}.'&'.'is_pbx_pilot=1');
if((exists $pilot->{total_count} && $pilot->{total_count}) || (exists $pilot->{content}->{total_count} && $pilot->{content}->{total_count} > 0) ){
    $fake_data_processed->{is_pbx_pilot} = 0;
    #remove pilot aliases to don't intersect with them. On subscriber termination admin adopt numbers, see ticket#4967
    $test_machine->request_patch(  [ { op => 'replace', path => '/alias_numbers', value => [] } ], $pilot->{location} );
}else{
    undef $pilot;
}
$test_machine->DATA_ITEM_STORE($fake_data_processed);
$test_machine->form_data_item();

my $remote_config = $test_machine->init_catalyst_config;
#modify time changes on every data change, and primary_number_id on every primary number change
my $put2get_check_params = { ignore_fields => $fake_data->data->{subscribers}->{update_change_fields} };


{
#20369
    diag("20369: informative error for the PUT method on subscriber with duplicated number;\n\n");
    my $members = $test_machine->check_create_correct( 2, sub{
        my $num = $_[1]->{i};
        $_[0]->{username} .= time().'_20369_'.$num ;
        $_[0]->{webusername} .= time().'_'.$num;
        $_[0]->{pbx_extension} .= '20369'.$num.Test::FakeData::seq;
        $_[0]->{primary_number}->{ac} .= $num;
        $_[0]->{is_pbx_group} = 0;
        $_[0]->{is_pbx_pilot} = ($pilot || $_[1]->{i} > 1)? 0 : 1;
        $_[0]->{alias_numbers} = [{ ac => '111'.$num, cc=> 11, sn => 11 },{ ac => '112'.$num, cc=> 11, sn => 11 }];
    } );
    #$members->[1]->{content}->{primary_number} = $members->[0]->{content}->{primary_number};
    #$members->[1]->{content}->{primary_number} = $members->[0]->{content}->{alias_numbers}->[0];
    $members->[1]->{content}->{alias_numbers}->[0] = $members->[0]->{content}->{alias_numbers}->[0];
    my ($res,$content,$request) = $test_machine->request_put(@{$members->[1]}{qw/content location/});
    $test_machine->http_code_msg(422, "Check that PUT existing number will return nice error", $res, $content);
    #Number '11-1111-11' already exists
    ok($content->{message} =~ /Number ['\-\d]+ already exists/, "check error message in body");
    #commit 581f1386b restricted deletion of PBX pilot before deleting all other subscribers
    $test_machine->request_delete($members->[1]->{location});
    $test_machine->request_delete($members->[0]->{location});
    $test_machine->clear_data_created();#fake data aren't registered in this test machine, so they will stay.
}
{
# create new subscribers from DATA_ITEM. Item is not created in the fake_data->process.
    $test_machine->check_create_correct( 1, sub{
        $_[0]->{username} .= time().'_'.$_[1]->{i} ;
        $_[0]->{pbx_extension} .= Test::FakeData::seq;
     } );
    $test_machine->check_bundle();
    $test_machine->check_get2put(undef,{},$put2get_check_params);
    $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
    #remove pilot aliases to don't intersect with them. On subscriber termination admin adopt numbers, see ticket#4967
    $pilot and $test_machine->request_patch(  [ { op => 'replace', path => '/alias_numbers', value => [] } ], $pilot->{location} );
}
#-------  MT#15441
{
    diag("15441");
    my $intentional_cli = '111'.time();
    my $intentional_primary_number = {
        'cc' => '111',
        'ac' => '222',
        'sn' => '1234'.time(),
    };

    #prepare preconditions: cli should differ from primary_nuber
    #my $subscriber = ($test_machine->get_created_first() || $fake_data->get_existent_item($test_machine->name) || $test_machine->get_item_hal());
    my $subscriber = $test_machine->check_create_correct(1, sub{
            my $num = $_[1]->{i};
            $_[0]->{username} .= time().'_15441' ;
            $_[0]->{webusername} .= time().'_15441';
            $_[0]->{pbx_extension} .= '15441'.Test::FakeData::seq;
            $_[0]->{primary_number}->{ac} .= $num;
            $_[0]->{customer_id} = $fake_data->get_id('customer_sipaccount');
        }
    )->[0];
    #print Dumper $subscriber;
    #die();
    $subscriber->{uri} = $subscriber->{location};
    my ($preferences, $preferences_put) = ({'uri' => '/api/subscriberpreferences/'.$test_machine->get_id_from_created($subscriber)}) x 2;
    (undef, $preferences->{content}) = $test_machine->check_item_get($preferences->{uri});
    $preferences->{content}->{cli} = $intentional_cli;
    (undef, $preferences_put->{content}) = $test_machine->request_put($preferences->{content},$preferences->{uri});

    is($preferences_put->{content}->{cli}, $intentional_cli, "check that cli was updated on subscriberpreferences put: $preferences_put->{content}->{cli} == $intentional_cli");

    my ($subscriber_put, $subscriber_get, $preferences_get);

    #1
    $subscriber->{content}->{primary_number} = $intentional_primary_number;
    $put2get_check_params->{compare_cb} = sub{
        #$put_in->{content}, $put_get_out->{content};
        my($put_in_content,$put_get_out_content) = @_;
        delete $put_get_out_content->{primary_number}->{number_id} if defined $put_get_out_content->{primary_number};
    };
    ($subscriber_put,$subscriber_get,$preferences_get) = $test_machine->put_and_get($subscriber, $preferences_put, $put2get_check_params);
    is($preferences_get->{content}->{cli}, $intentional_cli, "check that cli was preserved on subscriber phones update: $preferences_get->{content}->{cli} == $intentional_cli");
    #/1

    #2
    delete $subscriber->{content}->{primary_number};
    my ($res, $content_put) = $test_machine->request_put($subscriber->{content}, $subscriber->{uri});
    $test_machine->http_code_msg(422, "check that the primary_number cannot be deleted", $res, $content_put);
    #/2

    #now prepare preferences for zero situation, when synchronization will be restarted again
    #3
    delete $preferences->{content}->{cli};
    (undef, $preferences_put->{content}) = $test_machine->request_put($preferences->{content},$preferences->{uri});
    is($preferences_put->{content}->{cli}, undef, "check that cli was deleted on subscriberpreferences put with empty cli");
    #/3
    if($remote_config->{config}->{numbermanagement}->{auto_sync_cli}){
    #4
        $subscriber->{content}->{primary_number} = $intentional_primary_number;
        ($subscriber_put,$subscriber_get,$preferences_get) = $test_machine->put_and_get($subscriber, $preferences_put, $put2get_check_params);
        is($preferences_get->{content}->{cli}, number_as_string($intentional_primary_number), "check that cli was created on subscriber phones update: $preferences_get->{content}->{cli} == ".number_as_string($intentional_primary_number) );
    #/4
        $intentional_primary_number = {
            'cc' => '222',
            'ac' => '333',
            'sn' => '444'.time(),
        };
    #5
        $subscriber->{content}->{primary_number} = $intentional_primary_number;
        ($subscriber_put,$subscriber_get,$preferences_get) = $test_machine->put_and_get($subscriber, $preferences_put, $put2get_check_params );
        is($preferences_get->{content}->{cli}, number_as_string($intentional_primary_number), "check that cli was updated on subscriber phones update: $preferences_get->{content}->{cli} == ".number_as_string($intentional_primary_number) );
    #/5
    }
    $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
    #remove pilot aliases to don't intersect with them. On subscriber termination admin adopt numbers, see ticket#4967
    $pilot and $test_machine->request_patch(  [ { op => 'replace', path => '/alias_numbers', value => [] } ], $pilot->{location} );
}

if($remote_config->{config}->{features}->{cloudpbx}){
    {
    #TT#50802
        my $member_to_terminate;
        my $member_to_get_number;
        my $pilot_local;
        my $alias_numbers = [
                    { ac => '115', cc=> 15, sn => '50802' },
                    { ac => '116', cc=> 16, sn => '50802' },
                    { ac => '117', cc=> 17, sn => '50802' },
                    { ac => '118', cc=> 18, sn => '50802' },
                ];
        if(!$pilot) {
            diag("50802: create pilot");
            $pilot = $test_machine->check_create_correct( 1, sub{
                my $num = $_[1]->{i}.Test::FakeData::seq;
                $_[0]->{username} .= time().'_50802_'.$num ;
                $_[0]->{webusername} .= time().'_'.$num;
                $_[0]->{pbx_extension} .= '50802'.$num;
                $_[0]->{primary_number}->{ac} .= $num;
                $_[0]->{is_pbx_group} = 0;
                $_[0]->{is_pbx_pilot} = 1;
                $_[0]->{alias_numbers} = $alias_numbers;
            } )->[0];
            $pilot_local = $pilot;
        } else {
            $pilot_local = $pilot;

            $test_machine->request_patch(  [ { op => 'replace', path => '/alias_numbers', value => $alias_numbers } ], $pilot_local->{location} );
        }
        diag("50802: create member_to_terminate");
        $member_to_terminate = $test_machine->check_create_correct( 1, sub{
            my $num = $_[1]->{i}.Test::FakeData::seq;
            $_[0]->{username} .= time().'_50802_'.$num ;
            $_[0]->{webusername} .= time().'_'.$num;
            $_[0]->{pbx_extension} = '50802'.'1';
            $_[0]->{primary_number}->{sn} .= '50802';
            $_[0]->{is_pbx_group} = 0;
            $_[0]->{is_pbx_pilot} = 0;
            $_[0]->{alias_numbers} = [];#@{$alias_numbers}[0,1]
        } )->[0];
        #print Dumper $member_to_terminate;
        diag("50802: create member_to_get_number");
        $member_to_get_number = $test_machine->check_create_correct( 1, sub{
            my $num = $_[1]->{i}.Test::FakeData::seq;
            $_[0]->{username} .= time().'_50802_'.$num ;
            $_[0]->{webusername} .= time().'_'.$num;
            $_[0]->{pbx_extension} .= '50802'.$num;
            $_[0]->{primary_number}->{ac} .= $num;
            $_[0]->{is_pbx_group} = 0;
            $_[0]->{is_pbx_pilot} = 0;
            $_[0]->{alias_numbers} = [];#@{$alias_numbers}[2,3]
        } )->[0];
        my ($aliases) = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$pilot_local->{content}->{id}, 1)->{collection};
        ok(((scalar @$aliases) == 4),"50802: aliases of ".$pilot_local->{content}->{id}." are not empty:".(scalar @$aliases ));
        diag("50802: assign all aliases to member_to_terminate");
        foreach my $alias (@$aliases) {
            !$alias->{location} && next;
            diag("50802: check 'before' ownership, subscriber_id should be a pilot id:".$pilot_local->{content}->{id});
            is($pilot_local->{content}->{id},$alias->{content}->{subscriber_id},"50802: check ownership: prev owner id: ".$pilot_local->{content}->{id}."; alias subscriber_id:".$alias->{content}->{subscriber_id});
            $test_machine->check_patch2get([ { op => 'replace', path => '/subscriber_id', value => $member_to_terminate->{content}->{id} } ] , $alias->{location});
        }
        $aliases = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$member_to_terminate->{content}->{id}, 1)->{collection};
        ok(((scalar @$aliases) == 4),"50802: aliases of ".$member_to_terminate->{content}->{id}." are not empty:".(scalar @$aliases));
        diag("50802: assign all aliases to member_to_get_number");
        foreach my $alias (@$aliases) {
            !$alias->{location} && next;
            diag("50802: check 'before' ownership, subscriber_id should be a member_to_terminate id:".$member_to_terminate->{content}->{id});
            is($member_to_terminate->{content}->{id},$alias->{content}->{subscriber_id},"50802: check ownership: prev owner id: ".$member_to_terminate->{content}->{id}."; alias subscriber_id:".$alias->{content}->{subscriber_id});
            $test_machine->check_patch2get([ { op => 'replace', path => '/subscriber_id', value => $member_to_get_number->{content}->{id} } ] , $alias->{location});
        }
        $aliases = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$member_to_get_number->{content}->{id}, 1)->{collection};
        ok(((scalar @$aliases) == 4),"50802: aliases of ".$member_to_get_number->{content}->{id}." are not empty:".(scalar @$aliases ));
        diag("50802: assign all aliases to member_to_terminate again");
        foreach my $alias (@$aliases) {
            diag("50802: check 'before' ownership, subscriber_id should be a member_to_get_number id:".$member_to_get_number->{content}->{id});
            is($member_to_get_number->{content}->{id},$alias->{content}->{subscriber_id},"50802: check ownership: prev owner id: ".$member_to_get_number->{content}->{id}."; alias subscriber_id:".$alias->{content}->{subscriber_id});
            $test_machine->check_patch2get([ { op => 'replace', path => '/subscriber_id', value => $member_to_terminate->{content}->{id} } ] , $alias->{location});
        }

        my $terminated_primary_number = $member_to_terminate->{content}->{primary_number};
        diag("50802: primary_number of member_to_terminate");
        diag(Dumper($terminated_primary_number));

        diag("50802: terminate member_to_terminate");
        $test_machine->request_delete($member_to_terminate->{location});

        $aliases = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$pilot_local->{content}->{id}, 1)->{collection};
        #print Dumper $aliases;
        ok(((scalar @$aliases) == 4),"50802: aliases of ".$pilot_local->{content}->{id}." are not empty:".(scalar @$aliases ).". We returned aliases to pilot.");

        $pilot_local = $test_machine->get_item_hal('subscribers', '/api/subscribers/'.$pilot_local->{content}->{id}, 1);


        $terminated_primary_number->{is_devid} = json_true;
        $test_machine->check_patch2get([ { op => 'replace', path => '/alias_numbers', value => [@{$pilot_local->{content}->{alias_numbers}}, $terminated_primary_number] } ] , $pilot_local->{location},$put2get_check_params);

        $aliases = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$pilot_local->{content}->{id}, 1)->{collection};
        #print Dumper $aliases;
        ok(((scalar @$aliases) == 5),"50802: aliases of ".$pilot_local->{content}->{id}." are not empty:".(scalar @$aliases ).". We added ex-primary number as an alias.");

        diag("50802: steal numbers of terminated subscriber");
        foreach my $alias (@$aliases) {
            diag("50802: check ownership, subscriber_id should be a pilot id:".$pilot_local->{content}->{id});
            is($pilot_local->{content}->{id},$alias->{content}->{subscriber_id},"50802: check ownership: prev owner id: ".$pilot_local->{content}->{id}."; alias subscriber_id:".$alias->{content}->{subscriber_id});

            $test_machine->check_patch2get([ { op => 'replace', path => '/subscriber_id', value => $member_to_get_number->{content}->{id} } ] , $alias->{location});
        }

        $aliases = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$member_to_get_number->{content}->{id}, 1)->{collection};
        #print Dumper $aliases;
        ok(((scalar @$aliases) == 5),"50802: aliases of ".$member_to_get_number->{content}->{id}." are not empty:".(scalar @$aliases ).". We added ex-primary number as an alias.");

        $test_machine->request_patch(  [ { op => 'replace', path => '/alias_numbers', value => [] } ], $pilot->{location} );
        $test_machine->request_delete($member_to_get_number->{location});
        #die;
    }
    {#18601
        diag("18601: config->features->cloudpbx: ".$remote_config->{config}->{features}->{cloudpbx}.";\n");
        my $groups = $test_machine->check_create_correct( 3, sub{
            my $num = $_[1]->{i};
            $_[0]->{username} .= time().'_18601_'.$num ;
            $_[0]->{webusername} .= time().'_'.$num;
            $_[0]->{pbx_extension} .= '18601'.$num;
            $_[0]->{primary_number}->{ac} .= $num;
            $_[0]->{is_pbx_group} = 1;
            $_[0]->{is_pbx_pilot} = ($pilot || $_[1]->{i} > 1)? 0 : 1;
            delete $_[0]->{alias_numbers};
        } );
        my $members = $test_machine->check_create_correct( 3, sub{
            my $num = 3 + $_[1]->{i};
            $_[0]->{username} .= time().'_18601_'.$num ;
            $_[0]->{webusername} .= time().'_'.$num;
            $_[0]->{pbx_extension} .= '18601'.$num.Test::FakeData::seq;
            $_[0]->{primary_number}->{ac} .= $num;
            $_[0]->{is_pbx_pilot} = 0;
            $_[0]->{is_pbx_group} = 0;
            delete $_[0]->{alias_numbers};
        });
        $members->[1]->{content}->{pbx_group_ids} = [];
        diag("1. Check that member will return empty groups after put groups empty");
        my($member_put,$member_get) = $test_machine->check_put2get($members->[1],undef, $put2get_check_params);
        is_deeply( $members->[1]->{content}->{pbx_group_ids}, [], "Check that member will return empty groups after put groups empty");

        $members->[1]->{content}->{pbx_group_ids} = [map { $groups->[$_]->{content}->{id} } (2,1)];
        diag("2. Check that member will return groups as they were specified");
        #fix for the  5415 prevents changing members order in the group, this is why resulting groups order for the member may differ from the input
        #($member_put,$member_get) = $test_machine->check_put2get($members->[1], undef, $put2get_check_params);

        my($res,$content) = $test_machine->request_put(@{$members->[1]}{qw/content location/});
        $test_machine->http_code_msg(200, "PUT for members[1] was successful", $res, $content);
        my(undef, $members_1_after_touch) = $test_machine->check_item_get($members->[1]->{location});
        #print Dumper [$members->[1]->{content}, $members_1_after_touch];
        is_deeply( [sort @{$members->[1]->{content}->{pbx_group_ids}}], [sort @{$members_1_after_touch->{pbx_group_ids}}], "Check member groups after touch - the same cortege");

        $groups->[1]->{content}->{pbx_groupmember_ids} = [map { $members->[$_]->{content}->{id} } (2,1,0)];
        diag("3. Check that group will return members as they were specified");
        my($group_put,$group_get) = $test_machine->check_put2get($groups->[1], undef, $put2get_check_params);

        $groups->[1]->{content}->{pbx_groupmember_ids} = [];
        diag("4. Check that group will return empty members after put members empty");
        ($group_put,$group_get) = $test_machine->check_put2get($groups->[1], undef, $put2get_check_params);
    #5415 WF
        diag("5415: check that groups management doesn't change members order;\n");

        diag("5415:Set members order for the group;\n");
        $groups->[1]->{content}->{pbx_groupmember_ids} = [ map { $members->[$_]->{content}->{id} } ( 0, 2, 1 ) ];

        ($group_put,$group_get)= $test_machine->check_put2get($groups->[1], undef, $put2get_check_params);

        diag("5415:Touch one of the members;\n");
        $members->[2]->{content}->{pbx_group_ids} = [ map { $groups->[$_]->{content}->{id} } (2,1)];
        #my($res,$content) = $test_machine->check_put2get($members->[2]);
        #fix for the  5415 prevents changing members order in the group, this is why resulting groups order for the member may differ from the input
        ($res,$content) = $test_machine->request_put(@{$members->[2]}{qw/content location/});
        $test_machine->http_code_msg(200, "PUT for groups was successful", $res, $content);
        my(undef, $members_2_after_touch) = $test_machine->check_item_get($members->[2]->{location});
        is_deeply( [sort @{$members->[2]->{content}->{pbx_group_ids}}], [sort @{$members_2_after_touch->{pbx_group_ids}}], "Check member groups after touch - the same cortege");

        diag("5415:Check members order in the group;\n");
        my(undef, $group_get_after) = $test_machine->check_item_get($groups->[1]->{location});

        is_deeply($groups->[1]->{content}->{pbx_groupmember_ids}, $group_get_after->{pbx_groupmember_ids}, "Check group members order after touching it's member");

    #7453 - we have modifications, so we can check modify_timestamp
        ok(length($members_2_after_touch->{create_timestamp}) > 8 , "check create_timestamp not empty ".$members_2_after_touch->{create_timestamp});
        ok(length($members_2_after_touch->{modify_timestamp}) > 8 , "check modify_timestamp not empty ".$members_2_after_touch->{modify_timestamp});

        $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
    }
    {#TT#28510
        diag("28510: check subscriberadmin POST. Possible only for pbx subscriberadmin. ;\n");
        my $data = clone $test_machine->DATA_ITEM;
        $data->{administrative} = 1;
        my $pbxsubscriberadmin = $test_machine->check_create_correct(1, sub {
            my $num = $_[1]->{i};
            $_[0]->{administrative} = 1;
            $_[0]->{webusername} .= time().'_28510';
            $_[0]->{webpassword} = 'api_test_webpassword';
            $_[0]->{username} .= time().'_28510' ;
            $_[0]->{pbx_extension} .= '28510'.Test::FakeData::seq;
            $_[0]->{primary_number}->{ac} .= '28510';
            $_[0]->{is_pbx_group} = 0;
            $_[0]->{is_pbx_pilot} = ($pilot || $_[1]->{i} > 1)? 0 : 1;
        } )->[0];
        $test_machine->set_subscriber_credentials({ %{$pbxsubscriberadmin->{content}}, webpassword => 'api_test_webpassword' });
        $test_machine->runas('subscriber');
        my $subscriber = $test_machine->check_create_correct(1, sub {
            my $num = $_[1]->{i};
            $_[0]->{webusername} .= time().'_28510_1';
            $_[0]->{webpassword} = 'api_test_webpassword';
            $_[0]->{username} .= time().'_28510_1' ;
            $_[0]->{pbx_extension} .= '285101'.Test::FakeData::seq;
            $_[0]->{primary_number}->{ac} .= '28510';
            $_[0]->{is_pbx_group} = 1;
            $_[0]->{is_pbx_pilot} = 0;
            delete $_[0]->{profile_id};
            delete $_[0]->{profile_set_id};
            delete $_[0]->{alias_numbers};
        } )->[0];
        if (check_password_validation_config()) {
            my $subscriber_pwd = $test_machine->check_create_correct(1, sub {
                my $num = $_[1]->{i};
                $_[0]->{administrative} = 0;
                $_[0]->{webusername} = 'api_test_'.time().'_21818';
                $_[0]->{webpassword} = 'api_test_WEBpassword';
                $_[0]->{username}    = 'api_test_'.time().'_21818' ;
                $_[0]->{password}    = 'api_test_PWD'.time().'_21818' ;
                $_[0]->{pbx_extension} = '21818'.Test::FakeData::seq;
                $_[0]->{primary_number}->{ac} = '21818';
                $_[0]->{is_pbx_group} = 0;
                delete $_[0]->{profile_id};
                delete $_[0]->{profile_set_id};
                #sometimes we have pbx customer with disabled pbx feature in test data.
                $_[0]->{is_pbx_pilot} = 0;
                delete $_[0]->{alias_numbers};
            } )->[0];
            diag("21818: check password validation: run as \"subscriberadmin\" role;\n");
            test_password_validation($subscriber_pwd, {POST => 1});
            $test_machine->runas('admin');
            diag("21818: check password validation: run as \"admin\" role;\n");
            test_password_validation($subscriber_pwd);
            $test_machine->runas('reseller');
            diag("21818: check password validation: run as \"resellers\" role;\n");
            test_password_validation($subscriber_pwd);
        }
        $test_machine->runas('admin');
    }
    {#TT#34021
        my ($res,$content,$req);
        diag("34021: check subscriberadmin PUT and PATCH. Possible only for pbx subscriberadmin. Access privileges:".Dumper($remote_config->{config}->{acl}).";\n");

        $test_machine->runas('admin');

        my $resellers = $test_machine->get_collection_hal('resellers','/api/resellers/');
        my $wrong_reseller;
        foreach my $reseller (@{$resellers->{collection}}) {
            if ($reseller->{content}->{id} ne $fake_data->data->{customers}->{reseller_id}) {
                $wrong_reseller = $reseller;
                last;
            }
        }
        my $wrong_profile_sets = $fake_data->create( 'subscriberprofilesets', undef, { data => { 'subscriberprofilesets' => { reseller_id => $wrong_reseller->{content}->{id}}}} );
        my $wrong_profiles = $fake_data->create( 'subscriberprofiles', undef, { data => { 'subscriberprofiles' => { profile_set_id => $wrong_profile_sets->[0]->{content}->{id}, name => 'api_test_wrong_reseller_'.time() }}} );

        my $data = clone $test_machine->DATA_ITEM;
        $data->{administrative} = 1;
        $pilot = $test_machine->get_item_hal('subscribers','/api/subscribers/?customer_id='.$data->{customer_id}.'&'.'is_pbx_pilot=1');
        if(!$pilot->{total_count} || $pilot->{total_count} <= 0){
            undef $pilot;
        }
        my $pbxsubscriberadmin = $test_machine->check_create_correct(1, sub {
            my $num = $_[1]->{i};
            $_[0]->{administrative} = 1;
            $_[0]->{webusername} .= time().'_34021';
            $_[0]->{webpassword} = 'api_test_webpassword';
            $_[0]->{username} .= time().'_34021' ;
            $_[0]->{pbx_extension} .= '34021'.Test::FakeData::seq;
            $_[0]->{primary_number}->{ac} .= '34021';
            $_[0]->{is_pbx_group} = 0;
            $_[0]->{is_pbx_pilot} = ($pilot || $_[1]->{i} > 1)? 0 : 1;
            delete $_[0]->{alias_numbers};
        } )->[0];

        $test_machine->set_subscriber_credentials({ %{$pbxsubscriberadmin->{content}}, webpassword => 'api_test_webpassword' });
        $test_machine->runas('subscriber');
        my $subscriber = $test_machine->check_create_correct(1, sub {
            my $num = $_[1]->{i};
            $_[0]->{webusername} .= time().'_34021_1';
            $_[0]->{webpassword} = 'api_test_webpassword';
            $_[0]->{username} .= time().'_34021_1' ;
            $_[0]->{pbx_extension} .= '340211'.Test::FakeData::seq;
            $_[0]->{primary_number}->{ac} .= '34021';
            $_[0]->{is_pbx_group} = 0;
            $_[0]->{is_pbx_pilot} = 0;
            delete $_[0]->{profile_id};
            delete $_[0]->{profile_set_id};
            delete $_[0]->{alias_numbers};
        } )->[0];
        #if ($remote_config->{config}->{privileges}->{subscriberadmin}->{subscribers} =~/write/) {
        if ($remote_config->{config}->{features}->{cloudpbx}) {
            $test_machine->check_get2put($subscriber,{},$put2get_check_params);

            ($res,$content,$req) = $test_machine->request_patch(  [ { op => 'replace', path => '/display_name', value => 'patched 34021' } ], $subscriber->{location} );
            $test_machine->http_code_msg(200, "Check display_name patch for subscriberadmin", $res, $content);
            my $pilot_34021 = $test_machine->get_item_hal('subscribers','/api/subscribers/?customer_id='.$subscriber->{content}->{customer_id}.'&'.'is_pbx_pilot=1');
            my($res, $mod_34021_pilot) = $test_machine->request_patch([
                #to don't intersect with manual testing on the web
                { op => 'replace', path => '/profile_set_id', value => $fake_data->get_id('subscriberprofilesets') },
                { op => 'replace', path => '/profile_id', value => undef },#we will take default profile for profile_set
            ],
            $pilot_34021->{location} );

            #print Dumper [$wrong_reseller->{content},$wrong_profile_sets->[0]->{content},$wrong_profiles->[0]->{content}];
            #print Dumper [$subscriber->{content}];
            #subscriberadmin is not supposed to changed profile and profile_set. Subscriberadmin even don't contain these fields.

            my (undef, $subscriber_before) = $test_machine->check_item_get($subscriber->{location});
            ($res,$content,$req) = $test_machine->request_patch( [ { op => 'replace', path => '/profile_set_id', value => $wrong_profile_sets->[0]->{content}->{id} } ], $subscriber->{location} );
            $test_machine->http_code_msg(422, "Check profile_set_id patch for subscriberadmin is rejected", $res, $content,
                'Read-only field.s. for authenticated role: profile_set_id');
            ($res,$content,$req) = $test_machine->request_patch( [ { op => 'replace', path => '/profile_id', value => $wrong_profiles->[0]->{content}->{id} } ], $subscriber->{location} );
            $test_machine->http_code_msg(422, "Check profile_id patch for subscriberadmin is rejected", $res, $content,
                'Read-only field.s. for authenticated role: profile_id');
            (undef, $content) = $test_machine->check_item_get($subscriber->{location});
            is($content->{profile_id}, $subscriber_before->{profile_id}, "Check profile_id unchanged by subscriberadmin");

            #($res,$content,$req) = $test_machine->request_patch( [ { op => 'replace', path => '/alias_numbers', value => [{'cc' => '111','ac' => '222','sn' => '444'.time(),}] } ], $subscriber->{location} );
            #$test_machine->http_code_msg(200, "Check patch alias_numbers not belonging to the pilot for subscriberadmin", $res, $content);

            $test_machine->runas('admin');

            ($res,$content,$req) = $test_machine->request_patch( [ { op => 'replace', path => '/profile_set_id', value => $wrong_profile_sets->[0]->{content}->{id} } ], $subscriber->{location} );
            $test_machine->http_code_msg(422, "Check incorrect profile_set_id patch for administrator", $res, $content);

            ($res,$content,$req) = $test_machine->request_patch( [ { op => 'replace', path => '/profile_id', value => undef }, { op => 'replace', path => '/profile_set_id', value => undef } ], $subscriber->{location} );
            $test_machine->http_code_msg(200, "Check unset profile_id and profile_set_id patch for administrator", $res, $content);

            ($res,$content,$req) = $test_machine->request_patch( [ { op => 'replace', path => '/profile_id', value => $wrong_profiles->[0]->{content}->{id} } ], $subscriber->{location} );
            $test_machine->http_code_msg(422, "Check incorrect profile_id patch for administrator", $res, $content);
            ($res,$content,$req) = $test_machine->request_patch( [ { op => 'replace', path => '/profile_set_id', value => $wrong_profile_sets->[0]->{content}->{id} } ], $subscriber->{location} );
            $test_machine->http_code_msg(422, "Check profile_set_id patch for administrator", $res, $content);

            ($res,$content,$req) = $test_machine->request_patch( [ { op => 'replace', path => '/profile_id', value => $wrong_profiles->[0]->{content}->{id} } ], $subscriber->{location} );
            $test_machine->http_code_msg(422, "Check profile_id patch for administrator", $res, $content);

            $test_machine->check_patch2get( [ { op => 'replace', path => '/profile_id', value => $mod_34021_pilot->{content}->{profile_id} } ], $subscriber->{location}, $put2get_check_params );

            $test_machine->check_patch2get( [ { op => 'replace', path => '/profile_set_id', value => $mod_34021_pilot->{content}->{profile_set_id} } ], $subscriber->{location}, $put2get_check_params );

        } else {
            my($res,$content,$req) = $test_machine->request_patch(  [ { op => 'replace', path => '/display_name', value => 'patched 34021' } ], $subscriber->{location} );
            $test_machine->http_code_msg(403, "Check display_name patch for subscriberadmin", $res, $content, "Read-only resource for authenticated role");
        }
    }
    {#TT#43350
        diag("TT#43350 Test subscriberadmin access");
        diag("#------------------------ create subscribers of other customer of other reseller\n");
        my $test_machine_other_reseller = Test::Collection->new(
            name => 'subscribers',
            QUIET_DELETION => 1,
        );
        my $fake_data_other_reseller = Test::FakeData->new(
            keep_db_data => 1,
            test_machine => $test_machine_other_reseller,
        );
        $fake_data_other_reseller->load_collection_data('subscribers');
        $fake_data_other_reseller->load_data_from_script('domains');
        $fake_data_other_reseller->apply_data({
            'domains' => {
                'domain' => 'other_reseller_'.time().'.api_test',
            },
            'customers' => {
                'external_id' => 'other_reseller',
                'type'        => 'pbxaccount',
            },
            'customercontacts' => {
                'email' => 'other_reseller@email.com',
            },
            'contracts' => {
                'external_id' => 'other_reseller',
            },
            'resellers' => {
                'name' => 'other_reseller',
            },
            'subscribers' => {
                'is_pbx_pilot' => 0,
                'is_pbx_group' => 0,
                'webpassword'  => 'api_test_webpassword',
            },
            'subscriberprofilesets' => {
                'name' => 'other_reseller_subscriberprofileset',
            },
            'subscriberprofiles' => {
                'name' => 'other_reseller_subscriberprofile',
            },
        });
        my($subscribers_other_reseller, $subscriberadmins_other_reseller)
            = create_subs_and_subadmin($fake_data_other_reseller, $test_machine_other_reseller);

        diag("#------------------------ create subscriber of other customer\n");
        my $test_machine_other_customer = Test::Collection->new(
            name => 'subscribers',
            QUIET_DELETION => 1,
        );
        my $fake_data_other_customer = Test::FakeData->new(
            keep_db_data => 1,
            test_machine => $test_machine_other_customer,
        );
        $fake_data_other_customer->load_collection_data('subscribers');
        $fake_data_other_customer->apply_data({
            'customers' => {
                'external_id' => 'other_customer',
                'type'        => 'pbxaccount',
            },
            'customercontacts' => {
                'email' => 'other_customer@email.com',
            },
            'contracts' => {
                'external_id' => 'other_customer',
            },
            'subscribers' => {
                'is_pbx_pilot' => 0,
                'is_pbx_group' => 0,
                'webpassword'  => 'api_test_webpassword',
            },
            'subscriberprofilesets' => {
                'name' => 'other_customer_subscriberprofileset',
            },
            'subscriberprofiles' => {
                'name' => 'other_customer_subscriberprofile',
            },
        });
        my($subscribers_other_customer, $subscriberadmins_other_customer)
            = create_subs_and_subadmin($fake_data_other_customer, $test_machine_other_customer);

        diag("#------------------------ create usual subscriber of default test customer and reseller\n");
        my $fake_data_processed_old = $test_machine->DATA_ITEM_STORE;
        $fake_data->apply_data({
            'subscribers' => {
                'is_pbx_pilot' => 0,
                'is_pbx_group' => 0,
                'webpassword'  => 'api_test_webpassword',
            },
        });
        $fake_data_processed = $fake_data->process('subscribers');
        $test_machine->DATA_ITEM($fake_data_processed);
        #print Dumper $test_machine->DATA_ITEM;
        my($subscribers, $subscriberadmins)
            = create_subs_and_subadmin($fake_data, $test_machine);

        $test_machine->set_subscriber_credentials({ %{$subscriberadmins->[0]->{content}}, webpassword => 'api_test_webpassword' });
        $test_machine->runas('subscriber');
        diag("\n\n\nSUBSCRIBERADMIN ".$subscriberadmins->[0]->{content}->{id}.":");

        diag("#------------------------ subscriberadmin: attempt to create subscriber using other customer-reseller:\n");
        my($res,$content,$sub_create_attempt);
        $sub_create_attempt = $test_machine->check_create_correct(1,sub {
            my $num = $_[1]->{i};
            my $uniq = Test::FakeData::seq;
            $_[0]->{webusername} = '43350_'.$uniq;
            $_[0]->{username} = '43350_'.$uniq;
            $_[0]->{pbx_extension} = '43350'.$uniq;
            $_[0]->{primary_number}->{ac} = '43350'.$uniq;
            $_[0]->{is_pbx_pilot} = 0;
            $_[0]->{administrative} = 0;
            delete $_[0]->{profile_id};
            delete $_[0]->{profile_set_id};
            delete $_[0]->{alias_numbers};
            #$_[0]->{profile_id} = $subscribers->[0]->{content}->{profile_id};
            #print Dumper $_[0];
        }, $subscribers_other_reseller->[0]->{content})->[0];

        #print Dumper [
        #    $sub_create_attempt->{content},
        #    $subscribers_other_reseller->[0]->{content}->{customer_id},
        #    $subscriberadmins->[0]->{content}->{customer_id}];
        #print Dumper [$sub_create_attempt->{content}, $sub_create_attempt->{content_post}];

        ok(($sub_create_attempt->{content}->{customer_id} != $subscribers_other_reseller->[0]->{content}->{customer_id})
            && ($sub_create_attempt->{content}->{customer_id} == $subscriberadmins->[0]->{content}->{customer_id})
            && ($sub_create_attempt->{content_post}->{customer_id} == $subscribers_other_reseller->[0]->{content}->{customer_id}),
            "check that subscriberadminadmin customer_id ".$subscriberadmins->[0]->{content}->{customer_id}
            ." was applied instead of ".$sub_create_attempt->{content_post}->{customer_id});

        my $subadmin_create_uniq = Test::FakeData::seq;
        ($res, $content) = $test_machine->request_post({
            %{ $sub_create_attempt->{content_post} },
            webusername    => '43350_admin_'.$subadmin_create_uniq,
            username       => '43350_admin_'.$subadmin_create_uniq,
            pbx_extension  => '43351'.$subadmin_create_uniq,
            administrative => 1,
        });
        $test_machine->http_code_msg(422, "check that subscriberadmin can't create subscriberadmin", $res, $content,
            'Read-only field.s. for authenticated role: administrative');

        #here we have unexpected error:
        #Sep  9 22:37:02 sp1 ngcp-panel: DEBUG: username:43350_8_; resource.domain_id:101;item.domain_id:535;
        #Sep  9 22:37:02 sp1 ngcp-panel: ERROR: error 422 - Subscriber with this username does not exist in the domain.
        diag("#-------------------------- 1. Check customer_id management ----------");
        my ($content_get,$content_put, $content_patch);
        $test_machine->request_patch( [ {
                op     => 'replace',
                path   => '/customer_id',
                value  => $subscribers_other_customer->[0]->{content}->{customer_id}
            } ], $subscribers->[0]->{location});
        (undef,$content_get) = $test_machine->check_item_get($subscribers->[0]->{location});
        ok($content_get->{customer_id} == $fake_data->get_id('customers')
            && $content_get->{customer_id} != $subscribers_other_customer->[0]->{content}->{customer_id},
            "check that subscribersadmin can't apply foreign customer_id to own subscribers: "
            .$subscribers_other_customer->[0]->{content}->{customer_id}."=>".$content_get->{customer_id});

        $content_get->{customer_id} = $subscribers_other_customer->[0]->{content}->{customer_id};

        $test_machine->request_put( $content_get, $subscribers->[0]->{location});
        (undef,$content_get) = $test_machine->check_item_get($subscribers->[0]->{location});
        ok($content_get->{customer_id} == $fake_data->get_id('customers')
            && $content_get->{customer_id} != $subscribers_other_customer->[0]->{content}->{customer_id},
            "check that subscribersadmin can't apply foreign customer_id to own subscribers: "
            .$subscribers_other_customer->[0]->{content}->{customer_id}."=>".$content_get->{customer_id});

        diag("#-------------------------- 2. Check NUMBER management ----------");
        diag("#-------------------------- 2. 1. NUMBER: use other customer's primary number for create  ----------");

        ($res,$sub_create_attempt) = $test_machine->check_item_post(sub {
            my $num = $_[1]->{i};
            my $uniq = Test::FakeData::seq;
            $_[0]->{webusername} = '43350_'.$uniq;
            $_[0]->{username} = '43350_'.$uniq;
            $_[0]->{pbx_extension} = '43350'.$uniq;
            $_[0]->{primary_number}->{ac} = '43350'.$uniq;
            my $foreign_number = clone $subscribers_other_customer->[0]->{content}->{primary_number};
            delete $foreign_number->{number_id};
            delete $_[0]->{profile_id};
            $_[0]->{alias_numbers} = [$foreign_number];
            #print Dumper $_[0]->{alias_numbers};
        }, $subscribers_other_reseller->[0]->{content});
        $test_machine->http_code_msg(422, "Check subscriberadmin create subscriber using foreign primary_number", $res, $sub_create_attempt);
        #print Dumper $res;

        diag("#-------------------------- 2. 2. NUMBER: use other customer's primary number for edit (PUT)  ----------");

        $content_put = clone $content_get;
        $content_put->{alias_numbers} = [clone $subscribers_other_customer->[0]->{content}->{primary_number}];
        delete $content_put->{_links};
        delete $content_put->{alias_numbers}->[0]->{number_id};
        #print Dumper $content_put;
        ($res,$content_put) = $test_machine->request_put( $content_put, $subscribers->[0]->{location});
        $test_machine->http_code_msg(422, "check that subscribersadmin can't manage others customers numbers", $res, $content_put);
        (undef,$content_get) = $test_machine->check_item_get($subscribers->[0]->{location});
        delete $content_get->{alias_numbers}->[0]->{number_id};
        delete $subscribers_other_customer->[0]->{content}->{primary_number}->{number_id};
        # 0 if different, 1 if equal
        #k(!Data::Compare::Compare($content_get->{alias_numbers}->[0], $subscribers_other_customer->[0]->{content}->{primary_number}),
        #   "check that subscribersadmin can't manage others customers numbers. Other subscriber primary_number:\n"
        #   .Dumper($subscribers_other_customer->[0]->{content}->{primary_number})."\n=>\n".Dumper($content_get->{alias_numbers}->[0])
        #   );
        diag("#--------------------------3. Check PROFILE management ");
        diag("#--------------------------3. 1. PROFILE: Check attempt to apply other cutsomer's profile_id ------------ ");
        $content_put = clone $subscribers->[0]->{content};
        delete $content_put->{_links};
        $content_put->{profile_id} = $subscribers_other_customer->[0]->{content}->{profile_id};
        ($res, $content_put) = $test_machine->request_put( $content_put, $subscribers->[0]->{location});
        $test_machine->http_code_msg(422, "check that subscribersadmin others customers profile_id is rejected", $res, $content_put,
            'Read-only field.s. for authenticated role: .*profile_id');
        ($res,$content_get) = $test_machine->check_item_get($subscribers->[0]->{location});
        $content_get->{profile_id} //= '';
        ok($content_get->{profile_id} != $subscribers_other_customer->[0]->{content}->{profile_id},
            "check that subscribersadmin can't apply others customers profile_id. "
            .$subscribers_other_customer->[0]->{content}->{profile_id}." => ".$content_get->{profile_id});

        diag("#--------------------------3. 2. PROFILE: Check attempt to apply other profile_set profile_id ------------ ");

        my $test_machine_other_profile_set = Test::Collection->new(
            name => 'subscriberprofiles',
            QUIET_DELETION => 1,
        );
        my $fake_data_other_profile_set = Test::FakeData->new(
            keep_db_data => 1,
            test_machine => $test_machine_other_profile_set,
        );
        $fake_data_other_profile_set->load_collection_data('subscriberprofiles');
        $fake_data_other_profile_set->apply_data({
            'subscriberprofilesets' => {
                'name' => 'other_subscriberprofileset'.Test::FakeData::seq,
            },
            'subscriberprofiles' => {
                'name' => 'other_subscriberprofile'.Test::FakeData::seq,
            },
        });
        my $fake_data_other_profile_set_processed = $fake_data_other_profile_set->process('subscriberprofiles');
        #print Dumper ['create_subs_and_subadmin','fake_data_l_processed',$fake_data_l_processed];
        $test_machine_other_profile_set->DATA_ITEM($fake_data_other_profile_set_processed);
        $test_machine_other_profile_set->DATA_ITEM_STORE($fake_data_other_profile_set_processed);
        #just note - test_machine_other_profile_set is logged in as administrator, so we can create profileset and profile
        my $subscriberprofile_other_profile_set = $test_machine_other_profile_set->check_create_correct(1)->[0];

        $content_put = clone $subscribers->[0]->{content};
        delete $content_put->{_links};
        $content_put->{profile_id} = $subscriberprofile_other_profile_set->{content}->{id};
        $content_put->{display_name} = 'test_other_profileset_profile';
        ($res, $content_put) = $test_machine->request_put( $content_put, $subscribers->[0]->{location});
        $test_machine->http_code_msg(422, "check that subscribersadmin other profileset profile_id is rejected", $res, $content_put,
            'Read-only field.s. for authenticated role: .*profile_id');
        ($res,$content_get) = $test_machine->check_item_get($subscribers->[0]->{location});
        $content_get->{profile_id} //= '';
        ok($content_get->{profile_id} != $subscriberprofile_other_profile_set->{content}->{id},
            "check that subscribersadmin can't apply other profileset profile_id. "
            .$subscriberprofile_other_profile_set->{content}->{id}." => ".$content_get->{profile_id});

        diag("#--------------------------3. 3. PROFILE: Check attempt to apply correct profile_id ------------ ");

        my $test_machine_other_profile = Test::Collection->new(
            name => 'subscriberprofiles',
            QUIET_DELETION => 1,
        );
        my $fake_data_other_profile = Test::FakeData->new(
            keep_db_data => 1,
            test_machine => $test_machine_other_profile,
        );
        $fake_data_other_profile->load_collection_data('subscriberprofiles');
        $fake_data_other_profile->apply_data({
            'subscriberprofiles' => {
                'name' => 'other_subscriberprofile'.Test::FakeData::seq,
            },
        });
        my $fake_data_other_profile_processed = $fake_data_other_profile->process('subscriberprofiles');
        #print Dumper ['create_subs_and_subadmin','fake_data_l_processed',$fake_data_l_processed];
        $test_machine_other_profile->DATA_ITEM($fake_data_other_profile_processed);
        $test_machine_other_profile->DATA_ITEM_STORE($fake_data_other_profile_processed);
        #just note - test_machine_other_profile is logged in as administrator, so we can create profileset and profile
        my $subscriberprofile_other = $test_machine_other_profile->check_create_correct(1)->[0];

        $content_put = clone $subscribers->[0]->{content};
        delete $content_put->{_links};
        $content_put->{profile_id} = $subscriberprofile_other->{content}->{id};
        $content_put->{display_name} = 'test_other_profileset_profile';
        ($res, $content_put) = $test_machine->request_put( $content_put, $subscribers->[0]->{location});
        $test_machine->http_code_msg(422, "check that subscribersadmin profile from correct profile_set is rejected", $res, $content_put,
            'Read-only field.s. for authenticated role: .*profile_id');
        ($res,$content_get) = $test_machine->check_item_get($subscribers->[0]->{location});
        is($content_get->{profile_id}, $subscribers->[0]->{content}->{profile_id},
            "check that subscribersadmin can't change profile_id, even from the correct profile_set");


        diag("#--------------------------4. MISC: Check that subscriberadmin can manage something ------------ ");
        ($res,$content_patch) = $test_machine->request_patch(  [ { op => 'replace', path => '/display_name', value => 'patched_43350' } ], $subscribers->[0]->{location});
        $test_machine->http_code_msg(200, "check that subscribersadmin can manage available fields", $res, $content_patch);
        ($res,$content_get) = $test_machine->check_item_get($subscribers->[0]->{location});
        ok($content_get->{display_name} eq 'patched_43350',
            "check that subscribersadmin can manage display_name");

        diag("#-------------------------- 5. ACCESS other's customer subscribers ----------");
        foreach my $restricted_subscriber ($subscribers_other_reseller, $subscribers_other_customer) {
            my $location = $restricted_subscriber->[0]->{location};
            ($res,$content) = $test_machine->request_get($location);
            $test_machine->http_code_msg(404, "subscriberadmin: view subscriber of other customer:",$res,$content,
                "Entity 'subscriber' not found");
            ($res,$content) = $test_machine->request_put($sub_create_attempt->{content}, $location);
            $test_machine->http_code_msg(404, "subscriberadmin: put subscriber of other customer:",$res,$content,
                "Entity 'subscriber' not found");
            ($res,$content) = $test_machine->request_patch( [ { op => 'replace', path => '/display_name', value => 'patched 433050' } ], $location);
            $test_machine->http_code_msg(404, "subscriberadmin: patch subscriber of other customer:",$res,$content,
                "Entity 'subscriber' not found");
        }

        #$test_machine_other->set_subscriber_credentials($subscriber_other->{content});
        #$test_machine_other->runas('subscriber');
        #diag("\n\n\nSUBSCRIBER ".$subscriber_other->{content}->{id}.":");

        $test_machine->DATA_ITEM($fake_data_processed_old);

        $test_machine->clear_test_data_all();
        #if we failed with create checking (we s)
        #$test_machine->check_item_delete();

    }
}

#TT#21818 variant 2 - pbx feature off, subscriberadmin is read-only. No subscriber exists
if (!$remote_config->{config}->{features}->{cloudpbx}) {
    diag("21818: check password validation: subscriber and subscriberadmin are read-only roles;\n");
    $test_machine->runas('admin');
    my $subscriber = $test_machine->check_create_correct(1, sub {
        my $num = $_[1]->{i};
        $_[0]->{administrative} = 0;
        $_[0]->{webusername} = 'api_test_'.time().'_21818';
        $_[0]->{webpassword} = 'api_test_WEBpassword';
        $_[0]->{username}    = 'api_test_'.time().'_21818' ;
        $_[0]->{password}    = 'api_test_PWD_21818' ;
        $_[0]->{pbx_extension} = '21818'.Test::FakeData::seq;
        $_[0]->{primary_number}->{ac} = '21818';
        $_[0]->{is_pbx_group} = 0;
        #sometimes we have pbx customer with disabled pbx feature in test data.
        $_[0]->{is_pbx_pilot} = ($pilot || $_[1]->{i} > 1)? 0 : 1;
        delete $_[0]->{alias_numbers};
    } )->[0];
    if (check_password_validation_config()) {
        diag("21818: check password validation: run as \"admin\" role;\n");
        test_password_validation($subscriber);
        $test_machine->runas('reseller');
        diag("21818: check password validation: run as \"resellers\" role;\n");
        test_password_validation($subscriber);
        $test_machine->runas('admin');
    }
}
$test_machine->runas('admin');

#TT#8680
{
    diag("8680: check E164 fields format;\n");
    my $data = clone $test_machine->DATA_ITEM;
    #TT#9066
    $data->{primary_number} = ["12123132"];
    my($res,$content) = $test_machine->request_post( $data);
    $test_machine->http_code_msg(422, "Pimary number should be a hash", $res, $content);
    #MT#22853
    $data = clone $test_machine->DATA_ITEM;
    $data->{alias_numbers} = ["49221222899813", "49221222899814", "49221222899814"];
    ($res,$content) = $test_machine->request_post( $data);
    $test_machine->http_code_msg(422, "Alias numbers should be the hashes", $res, $content);
}

#subscriber/subscriberadmin restricted fields and the PBX numbers pool
{
    diag("check subscriber/subscriberadmin restricted fields and the PBX numbers pool;\n");
    my $admin = Test::Collection->new(name => 'subscribers');
    $admin->runas('admin');
    my $user = Test::Collection->new(name => 'subscribers');
    # the client certificate file is shared by all Test::Collection instances and removed on a role switch,
    # drop the stale one from the ua before fetching it again
    my $admin_cert = sub {
        my ($machine) = @_;
        $machine->ua->ssl_opts(SSL_cert_file => undef, SSL_key_file => undef);
        $machine->init_ssl_cert($machine->ua, 'admin');
        return $machine;
    };
    my $as_admin = sub { return $admin_cert->($admin) };

    my $ts = time();
    my $base = substr($ts, -6);
    my ($cc, $ac) = ('43', '99');
    my $password = 'Rf9#kLm2$Qx7!pZa';
    my ($res, $content, $own);

    my $number = sub { return { cc => $cc, ac => $ac, sn => $base . $_[0] } };
    my $numbers = sub { return [ map { number_as_string($number->($_)) } @_ ] };
    my $created_id = sub { my ($id) = ($_[0]->header('Location') // '') =~ m{/(\d+)$}; return $id };
    my $admin_post = sub {
        my ($collection, $data, $name) = @_;
        my ($res, $content) = $as_admin->()->request_post($data, "/api/$collection/");
        is($res->code, 201, "admin: create $name") or diag(explain $content);
        return $created_id->($res);
    };
    my $admin_get = sub {
        my ($res, $content) = $as_admin->()->request_get("/api/subscribers/$_[0]");
        is($res->code, 200, "admin: get subscriber $_[0]");
        return $content;
    };
    my $state = sub {
        my $s = $admin_get->($_[0]);
        return {
            (map { $_ => $s->{$_} }
                qw/lock status administrative profile_set_id profile_id pbx_extension display_name timezone email/),
            primary_number => $s->{primary_number} ? number_as_string($s->{primary_number}) : undef,
            aliases => [ sort map { number_as_string($_) . ($_->{is_devid} ? ':devid' : '') }
                @{ $s->{alias_numbers} // [] } ],
        };
    };
    my $aliases = sub { return [ sort map { s/:devid$//r } @{ $state->($_[0])->{aliases} } ] };
    my $number_exists = sub {
        my $n = $number->($_[0]);
        my ($res, $content) = $as_admin->()->request_get("/api/numbers/?cc=$n->{cc}&ac=$n->{ac}&sn=$n->{sn}");
        return ($content->{total_count} // 0) > 0;
    };
    my $login = sub {
        $user->set_subscriber_credentials({ %{$_[0]}, webpassword => $password });
        $user->runas('subscriber');
    };
    my $code_ok = sub {
        my ($res, $content, $code, $name, $message) = @_;
        is($res->code, $code, "$name: $code") or diag(explain $content);
        like((ref $content eq 'HASH' ? $content->{message} : undef) // '', qr/\Q$message\E/, "$name: message")
            if defined $message;
    };
    my $patch = sub { return $user->request_patch($_[1], "/api/subscribers/$_[0]") };
    my $admin_patch = sub { return $as_admin->()->request_patch($_[1], "/api/subscribers/$_[0]") };
    # the request succeeds, restricted fields keep their values, only %changed is applied
    my $patch_state_ok = sub {
        my ($id, $ops, $name, %changed) = @_;
        my $before = $state->($id);
        my ($res, $content) = $patch->($id, $ops);
        is($res->code, 200, "$name: 200") or diag(explain $content);
        is_deeply($state->($id), { %{$before}, %changed }, "$name: state");
    };
    my $put_state_ok = sub {
        my ($id, $data, $name, %changed) = @_;
        my $before = $state->($id);
        my ($res, $content) = $user->request_put($data, "/api/subscribers/$id");
        is($res->code, 200, "$name: 200") or diag(explain $content);
        is_deeply($state->($id), { %{$before}, %changed }, "$name: state");
    };
    # the request is rejected, nothing changes
    my $readonly_message = sub { return 'Read-only field(s) for authenticated role: ' . join(', ', @_) };
    my $rejected_ok = sub {
        my ($method, $id, $data, $name, @fields) = @_;
        my $before = $state->($id);
        my ($res, $content) = $method eq 'PUT'
            ? $user->request_put($data, "/api/subscribers/$id")
            : $patch->($id, $data);
        $code_ok->($res, $content, 422, $name);
        is(ref $content eq 'HASH' ? $content->{message} : undef, $readonly_message->(@fields), "$name: message");
        is_deeply($state->($id), $before, "$name: state");
    };
    my $rejected_cases = sub {
        my ($id, $name, @cases) = @_;
        $rejected_ok->('PATCH', $id, $_->[1], "$name PATCH $_->[0] rejected", $_->[2]) for @cases;
    };
    my $own_get = sub {
        my ($res, $content) = $user->request_get("/api/subscribers/$_[0]");
        my $resource = clone($content);
        delete $resource->{_links};
        return $resource;
    };
    my $visibility_ok = sub {
        my ($id, $name) = @_;
        my ($res, $content) = $user->request_get("/api/subscribers/$id");
        ok(exists $content->{administrative} && exists $content->{profile_id},
            "$name: administrative and profile_id visible");
        ok(!exists $content->{profile_set_id} && !exists $content->{lock},
            "$name: profile_set_id and lock hidden");
    };
    my $not_found_ok = sub {
        my ($id, $name, @methods) = @_;
        for my $method (@methods) {
            my ($res, $content);
            if ($method eq 'PATCH') {
                ($res, $content) = $patch->($id, [ { op => 'replace', path => '/display_name', value => 'not applied' } ]);
            } elsif ($method eq 'PUT') {
                ($res, $content) = $user->request_put({ display_name => 'not applied' }, "/api/subscribers/$id");
            } elsif ($method eq 'DELETE') {
                (undef, $res, $content) = $user->request_delete("/api/subscribers/$id");
            } else {
                ($res, $content) = $user->request_get("/api/subscribers/$id");
            }
            $code_ok->($res, $content, 404, "$name: $method", "Entity 'subscriber' not found");
        }
    };
    my $non_existent_id = 2**31 - 1;
    my %restricted_ops = (
        'status locked'     => [ { op => 'replace', path => '/status', value => 'locked' } ],
        'status terminated' => [ { op => 'replace', path => '/status', value => 'terminated' } ],
        'lock 4'            => [ { op => 'add', path => '/lock', value => 4 } ],
        'lock null'         => [ { op => 'add', path => '/lock', value => undef } ],
        'primary_number'    => [ { op => 'replace', path => '/primary_number', value => $number->('03') } ],
        'add alias'         => [ { op => 'add', path => '/alias_numbers/-', value => $number->('04') } ],
        'add pool alias'    => [ { op => 'add', path => '/alias_numbers/-', value => $number->('91') } ],
        'remove alias'      => [ { op => 'remove', path => '/alias_numbers/0' } ],
        'alias is_devid'    => [ { op => 'replace', path => '/alias_numbers/0/is_devid', value => JSON::false } ],
        'copy primary to alias' => [ { op => 'copy', from => '/primary_number', path => '/alias_numbers/-' } ],
        'pbx_extension'     => [ { op => 'add', path => '/pbx_extension', value => '19' } ],
        'profile_id'        => [ { op => 'replace', path => '/profile_id', value => undef } ],
        'profile_set_id'    => [ { op => 'add', path => '/profile_set_id', value => undef } ],
        'administrative on' => [ { op => 'replace', path => '/administrative', value => JSON::true } ],
        'administrative off' => [ { op => 'replace', path => '/administrative', value => JSON::false } ],
    );
    my %restricted_field = (
        (map { $_ => 'alias_numbers' } grep { /alias/ } keys %restricted_ops),
        (map { $_ => (split / /)[0] } grep { !/alias/ } keys %restricted_ops),
    );
    my $cases = sub { return map { [ $_, $restricted_ops{$_}, $restricted_field{$_} ] } @_ };

    #---- setup (admin)
    my $domain = "restricted-$ts.test";
    $admin_post->('domains', { domain => $domain, reseller_id => 1 }, 'domain');
    my $contact_id = $admin_post->('customercontacts', { reseller_id => 1, email => "restricted-$ts\@test.invalid" }, 'contact');
    ($res, $content) = $as_admin->()->request_get('/api/billingprofiles/?reseller_id=1&rows=1');
    my $billing_profile_id = $content->{_embedded}->{'ngcp:billingprofiles'}->[0]->{id};
    my %customer;
    my $create_customer = sub {
        $customer{$_[0]} = $admin_post->('customers', {
            contact_id         => $contact_id,
            billing_profile_id => $billing_profile_id,
            type               => $_[0],
            status             => 'active',
        }, "$_[0] customer");
    };
    $create_customer->('sipaccount');
    my $profile_set_id = $admin_post->('subscriberprofilesets',
        { reseller_id => 1, name => "restricted_set_$ts", description => 'restricted' }, 'profile set');
    my $profile_id = $admin_post->('subscriberprofiles', {
        profile_set_id => $profile_set_id,
        name           => "restricted_profile_$ts",
        description    => 'restricted',
        set_default    => JSON::true,
        attributes     => [ 'ncos' ],
    }, 'profile');
    my $create_subscriber = sub {
        my ($name, $customer_id, %data) = @_;
        my $subscriber = {
            customer_id    => $customer_id,
            domain         => $domain,
            username       => "restricted_${name}_$ts",
            webusername    => "restricted_${name}_$ts",
            password       => $password,
            webpassword    => $password,
            status         => 'active',
            profile_set_id => $profile_set_id,
            profile_id     => $profile_id,
            %data,
        };
        $subscriber->{id} = $admin_post->('subscribers', $subscriber, "subscriber $name");
        return $subscriber;
    };
    my $sip = $create_subscriber->('sip', $customer{sipaccount},
        primary_number => $number->('01'),
        alias_numbers  => [ { %{ $number->('02') }, is_devid => JSON::true } ],
    );
    my $sip_admin = $create_subscriber->('sip_admin', $customer{sipaccount}, administrative => 1, primary_number => $number->('06'));
    my $sip_other = $create_subscriber->('sip_other', $customer{sipaccount}, primary_number => $number->('07'));
    ($res, $content) = $admin_patch->($sip->{id}, [ { op => 'replace', path => '/lock', value => 2 } ]);
    $code_ok->($res, $content, 200, 'admin: lock sip subscriber');

    #---- subscriber (sipaccount), own resource
    $login->($sip);
    $visibility_ok->($sip->{id}, 'subscriber: own GET');
    $rejected_cases->($sip->{id}, 'subscriber:', $cases->(
        'status locked', 'status terminated', 'lock 4', 'lock null', 'primary_number', 'add alias', 'remove alias',
        'alias is_devid', 'copy primary to alias', 'pbx_extension', 'profile_id', 'profile_set_id', 'administrative on'));
    $rejected_ok->('PATCH', $sip->{id}, [
        { op => 'replace', path => '/email', value => "restricted-sip-$ts\@test.invalid" },
        { op => 'replace', path => '/status', value => 'locked' },
        { op => 'replace', path => '/primary_number', value => $number->('03') },
    ], 'subscriber: PATCH email with restricted fields', qw/status primary_number/);
    $patch_state_ok->($sip->{id}, [
        { op => 'replace', path => '/email', value => "restricted-sip-$ts\@test.invalid" },
        { op => 'replace', path => '/status', value => 'active' },
        { op => 'add', path => '/lock', value => 2 },
        { op => 'replace', path => '/administrative', value => JSON::false },
        { op => 'replace', path => '/alias_numbers/0/is_devid', value => JSON::true },
        { op => 'replace', path => '/primary_number', value => $number->('01') },
    ], 'subscriber: PATCH email with unchanged restricted fields', email => "restricted-sip-$ts\@test.invalid");
    $own = $own_get->($sip->{id});
    $put_state_ok->($sip->{id}, $own, 'subscriber: PUT own GET representation');
    $put_state_ok->($sip->{id}, { %{$own}, lock => 2, timezone => 'Europe/Vienna' },
        'subscriber: PUT with unchanged lock', timezone => 'Europe/Vienna');
    $rejected_ok->('PUT', $sip->{id}, {
        %{$own},
        status         => 'locked',
        lock           => 4,
        primary_number => $number->('05'),
        alias_numbers  => [],
        administrative => JSON::true,
        profile_id     => undef,
        timezone       => 'Europe/Paris',
    }, 'subscriber: PUT with changed restricted fields', qw/lock status primary_number alias_numbers profile_id administrative/);
    $rejected_ok->('PUT', $sip->{id}, { %{$own}, alias_numbers => [ { %{ $number->('02') }, is_devid => JSON::false } ] },
        'subscriber: PUT alias is_devid', 'alias_numbers');
    delete @{$own}{qw/primary_number alias_numbers status lock pbx_extension profile_set_id profile_id administrative/};
    $own->{timezone} = 'Europe/Berlin';
    $put_state_ok->($sip->{id}, $own, 'subscriber: PUT without restricted fields', timezone => 'Europe/Berlin');
    is($state->($sip->{id})->{lock}, 2, 'subscriber: lock still 2');
    is_deeply($state->($sip->{id})->{aliases}, [ number_as_string($number->('02')) . ':devid' ], 'subscriber: alias and is_devid kept');
    ok(!$number_exists->('03') && !$number_exists->('04') && !$number_exists->('05'), 'subscriber: no numbers created');
    $not_found_ok->($sip_other->{id}, 'subscriber: other subscriber', qw/GET PATCH PUT/);
    $not_found_ok->($non_existent_id, 'subscriber: non-existent subscriber', qw/GET PATCH PUT/);
    is($state->($sip_other->{id})->{display_name}, undef, 'subscriber: other subscriber unchanged');

    #---- subscriberadmin (sipaccount), own resource
    $login->($sip_admin);
    $visibility_ok->($sip_admin->{id}, 'sip subscriberadmin: own GET');
    $rejected_cases->($sip_admin->{id}, 'sip subscriberadmin: own', $cases->(
        'status locked', 'status terminated', 'lock 4', 'primary_number', 'add alias', 'profile_id', 'administrative off'));
    $own = $own_get->($sip_admin->{id});
    $put_state_ok->($sip_admin->{id}, $own, 'sip subscriberadmin: PUT own GET representation');
    ok(!$number_exists->('03') && !$number_exists->('04'), 'sip subscriberadmin: no numbers created');
    $not_found_ok->($non_existent_id, 'sip subscriberadmin: non-existent subscriber', qw/GET PATCH PUT DELETE/);

    #---- subscriberadmin (sipaccount) on another subscriber of the customer
    if (($remote_config->{config}->{privileges}->{subscriberadmin}->{subscribers} // '') =~ /write/) {
        $patch_state_ok->($sip_other->{id}, [ { op => 'add', path => '/lock', value => 3 } ],
            'sip subscriberadmin: other PATCH lock 3', lock => 3);
        $rejected_cases->($sip_other->{id}, 'sip subscriberadmin: other', $cases->('profile_id', 'administrative on'));
        ($res, $content) = $patch->($sip_other->{id}, [ { op => 'add', path => '/alias_numbers/-', value => $number->('09') } ]);
        $code_ok->($res, $content, 422, 'sip subscriberadmin: other PATCH new alias (no pool without pilot)',
            "Invalid 'alias_numbers', not available in the PBX pool: " . number_as_string($number->('09')));
        ok(!$number_exists->('09'), 'sip subscriberadmin: new number not created');
        ($res, $content) = $user->request_post({
            customer_id    => $customer{sipaccount},
            domain         => $domain,
            username       => "restricted_sip_new_$ts",
            password       => $password,
            primary_number => $number->('08'),
            administrative => JSON::true,
        }, '/api/subscribers/');
        $code_ok->($res, $content, 422, 'sip subscriberadmin: POST administrative');
        is($content->{message}, $readonly_message->('administrative'), 'sip subscriberadmin: POST administrative: message');
        ($res, $content) = $user->request_post({
            customer_id    => $customer{sipaccount},
            domain         => $domain,
            username       => "restricted_sip_new_$ts",
            password       => $password,
            primary_number => $number->('08'),
        }, '/api/subscribers/');
        $code_ok->($res, $content, 201, 'sip subscriberadmin: POST with write privileges');
        my $sip_new_id = $created_id->($res);
        is($admin_get->($sip_new_id)->{customer_id}, $customer{sipaccount}, 'sip subscriberadmin: POST in own customer');
        $as_admin->()->request_delete("/api/subscribers/$sip_new_id");
    } else {
        my $before = $state->($sip_other->{id});
        for my $case ([ 'lock 3', [ { op => 'add', path => '/lock', value => 3 } ] ],
                      [ 'display_name', [ { op => 'replace', path => '/display_name', value => 'not applied' } ] ]) {
            ($res, $content) = $patch->($sip_other->{id}, $case->[1]);
            $code_ok->($res, $content, 403, "sip subscriberadmin: other PATCH $case->[0] without write privileges",
                'Read-only resource for authenticated role');
        }
        is_deeply($state->($sip_other->{id}), $before, 'sip subscriberadmin: other unchanged');
        ($res, $content) = $user->request_post({
            customer_id    => $customer{sipaccount},
            domain         => $domain,
            username       => "restricted_sip_new_$ts",
            password       => $password,
            primary_number => $number->('08'),
        }, '/api/subscribers/');
        $code_ok->($res, $content, 403, 'sip subscriberadmin: POST without write privileges',
            'Read-only resource for authenticated role');
        ($res, $content) = $as_admin->()->request_get("/api/subscribers/?username=restricted_sip_new_$ts");
        is($content->{total_count}, 0, 'sip subscriberadmin: POST without write privileges created nothing');
    }

    #---- admin is not restricted
    ($res, $content) = $admin_patch->($sip->{id}, [
        { op => 'replace', path => '/lock', value => 3 },
        { op => 'add', path => '/alias_numbers/-', value => $number->('97') },
        { op => 'replace', path => '/primary_number', value => $number->('98') },
        { op => 'replace', path => '/profile_id', value => undef },
        { op => 'replace', path => '/profile_set_id', value => undef },
    ]);
    $code_ok->($res, $content, 200, 'admin: PATCH lock, alias_numbers, primary_number, profile');
    my $admin_state = $state->($sip->{id});
    is($admin_state->{lock}, 3, 'admin: lock changed');
    is($admin_state->{primary_number}, number_as_string($number->('98')), 'admin: primary number changed');
    ok((any { $_ eq number_as_string($number->('97')) } @{ $admin_state->{aliases} }), 'admin: new alias assigned');
    ok(!defined $admin_state->{profile_id} && !defined $admin_state->{profile_set_id}, 'admin: profile removed');
    my $admin_put = clone($admin_get->($sip->{id}));
    delete $admin_put->{_links};
    ($res, $content) = $as_admin->()->request_put($admin_put, "/api/subscribers/$sip->{id}");
    $code_ok->($res, $content, 200, 'admin: PUT GET representation');

    if ($remote_config->{config}->{features}->{cloudpbx}) {
        $create_customer->('pbxaccount');
        my $pilot = $create_subscriber->('pilot', $customer{pbxaccount},
            administrative => 1,
            is_pbx_pilot   => 1,
            primary_number => { cc => $cc, ac => $ac, sn => $base },
            alias_numbers  => [ map { $number->($_) } qw/91 92 93 94/ ],
        );
        my $subadmin = $create_subscriber->('subadmin', $customer{pbxaccount}, administrative => 1, pbx_extension => '10');
        my $seat_t = $create_subscriber->('seat_t', $customer{pbxaccount}, pbx_extension => '11', alias_numbers => [ $number->('81') ]);
        my $seat_u = $create_subscriber->('seat_u', $customer{pbxaccount}, pbx_extension => '12', alias_numbers => [ $number->('82') ]);
        my $group = $create_subscriber->('group', $customer{pbxaccount}, pbx_extension => '20', is_pbx_group => 1);
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/91 92 93 94/), 'setup: pilot pool');

        #---- subscriber (PBX seat), own resource
        $login->($seat_t);
        $visibility_ok->($seat_t->{id}, 'seat: own GET');
        $rejected_cases->($seat_t->{id}, 'seat:', $cases->('pbx_extension', 'primary_number', 'add pool alias', 'status locked'));
        $own = $own_get->($seat_t->{id});
        $put_state_ok->($seat_t->{id}, $own, 'seat: PUT own GET representation');
        $rejected_ok->('PUT', $seat_t->{id}, { %{$own}, pbx_extension => '19', alias_numbers => [] },
            'seat: PUT with changed restricted fields', qw/alias_numbers pbx_extension/);
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/91 92 93 94/), 'seat: pilot pool unchanged');

        #---- subscriberadmin (non-pilot), own resource
        $login->($subadmin);
        $visibility_ok->($subadmin->{id}, 'subscriberadmin: own GET');
        $rejected_cases->($subadmin->{id}, 'subscriberadmin: own', $cases->(
            'status terminated', 'lock 4', 'primary_number', 'add pool alias', 'profile_id', 'administrative off'));
        for my $case ([ 'seat', '11' ], [ 'group', '20' ]) {
            ($res, $content) = $patch->($subadmin->{id}, [ { op => 'replace', path => '/pbx_extension', value => $case->[1] } ]);
            $code_ok->($res, $content, 422, "subscriberadmin: own PATCH pbx_extension of a $case->[0]",
                'The pbx_extension already exists for this customer.');
        }
        $patch_state_ok->($subadmin->{id}, [ { op => 'replace', path => '/pbx_extension', value => '19' } ],
            'subscriberadmin: own PATCH free pbx_extension', pbx_extension => '19', primary_number => number_as_string($number->('19')));
        $patch_state_ok->($subadmin->{id}, [ { op => 'replace', path => '/pbx_extension', value => '10' } ],
            'subscriberadmin: own PATCH pbx_extension back', pbx_extension => '10', primary_number => number_as_string($number->('10')));

        $not_found_ok->($sip->{id}, 'subscriberadmin: other customer subscriber', qw/GET PATCH PUT DELETE/);
        $not_found_ok->($non_existent_id, 'subscriberadmin: non-existent subscriber', qw/GET PATCH PUT DELETE/);
        is($state->($sip->{id})->{status}, 'active', 'subscriberadmin: other customer subscriber not terminated');

        #---- subscriberadmin (non-pilot) on the pilot
        $visibility_ok->($pilot->{id}, 'subscriberadmin: pilot GET');
        $rejected_cases->($pilot->{id}, 'subscriberadmin: pilot', $cases->(
            'status terminated', 'status locked', 'lock 4', 'primary_number', 'remove alias', 'profile_id', 'administrative off'));
        $patch_state_ok->($pilot->{id}, [ { op => 'replace', path => '/display_name', value => 'Restricted Pilot' } ],
            'subscriberadmin: pilot PATCH display_name', display_name => 'Restricted Pilot');
        my (undef, $del_res) = $user->request_delete("/api/subscribers/$pilot->{id}");
        is($del_res->code, 403, 'subscriberadmin: DELETE pilot: 403');
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/91 92 93 94/), 'subscriberadmin: pilot pool unchanged');

        #---- subscriberadmin (non-pilot) on its subscribers: lock, status, pbx_extension, profile
        $visibility_ok->($seat_t->{id}, 'subscriberadmin: seat GET');
        $patch_state_ok->($seat_t->{id}, [ { op => 'add', path => '/lock', value => 3 } ], 'subscriberadmin: seat PATCH lock 3', lock => 3);
        for my $lock (0, 6, 'x') {
            ($res, $content) = $patch->($seat_t->{id}, [ { op => 'add', path => '/lock', value => $lock } ]);
            $code_ok->($res, $content, 422, "subscriberadmin: seat PATCH lock $lock", "field='lock'");
        }
        $patch_state_ok->($seat_t->{id}, [ { op => 'replace', path => '/display_name', value => 'Seat T' } ],
            'subscriberadmin: seat PATCH without lock keeps it', display_name => 'Seat T');
        $patch_state_ok->($seat_t->{id}, [ { op => 'add', path => '/lock', value => undef } ],
            'subscriberadmin: seat PATCH lock null', lock => undef);
        $patch_state_ok->($seat_t->{id}, [ { op => 'replace', path => '/status', value => 'locked' } ],
            'subscriberadmin: seat PATCH status locked', status => 'locked', lock => 4);
        $patch_state_ok->($seat_t->{id}, [ { op => 'replace', path => '/status', value => 'active' }, { op => 'add', path => '/lock', value => undef } ],
            'subscriberadmin: seat PATCH status active', status => 'active', lock => undef);
        $patch_state_ok->($seat_t->{id}, [ { op => 'replace', path => '/status', value => 'locked' } ],
            'subscriberadmin: seat PATCH status locked again', status => 'locked', lock => 4);
        my $seat_lock_put = $own_get->($seat_t->{id});
        delete @{$seat_lock_put}{qw/status lock/};
        $put_state_ok->($seat_t->{id}, $seat_lock_put, 'subscriberadmin: seat PUT without lock and status resets them',
            status => 'active', lock => undef);
        $rejected_cases->($seat_t->{id}, 'subscriberadmin: seat', $cases->('profile_id', 'profile_set_id', 'administrative on'));
        $patch_state_ok->($seat_t->{id}, [ { op => 'replace', path => '/pbx_extension', value => '15' } ],
            'subscriberadmin: seat PATCH pbx_extension', pbx_extension => '15', primary_number => number_as_string($number->('15')));
        $rejected_ok->('PATCH', $seat_t->{id}, [ { op => 'replace', path => '/primary_number', value => $number->('05') } ],
            'subscriberadmin: seat PATCH primary_number', 'primary_number');
        $rejected_ok->('PATCH', $seat_t->{id}, [
            { op => 'replace', path => '/pbx_extension', value => '14' },
            { op => 'replace', path => '/primary_number', value => $number->('05') },
        ], 'subscriberadmin: seat PATCH pbx_extension with other primary_number', 'primary_number');
        $patch_state_ok->($seat_t->{id}, [
            { op => 'replace', path => '/pbx_extension', value => '14' },
            { op => 'replace', path => '/primary_number', value => $number->('14') },
        ], 'subscriberadmin: seat PATCH pbx_extension with derived primary_number',
            pbx_extension => '14', primary_number => number_as_string($number->('14')));
        my $seat_ext_put = $own_get->($seat_t->{id});
        $put_state_ok->($seat_t->{id}, { %{$seat_ext_put}, pbx_extension => '15' },
            'subscriberadmin: seat PUT pbx_extension with stored primary_number',
            pbx_extension => '15', primary_number => number_as_string($number->('15')));

        #---- subscriberadmin (non-pilot) on its subscribers: numbers pool
        $patch_state_ok->($seat_t->{id}, [ { op => 'add', path => '/alias_numbers/-', value => $number->('91') } ],
            'subscriberadmin: seat PATCH assign pool number', aliases => $numbers->(qw/81 91/));
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/92 93 94/), 'subscriberadmin: pool number moved from the pilot');
        for my $case ([ 'new number', '95' ], [ 'number of other seat', '82' ]) {
            ($res, $content) = $patch->($seat_t->{id}, [ { op => 'add', path => '/alias_numbers/-', value => $number->($case->[1]) } ]);
            $code_ok->($res, $content, 422, "subscriberadmin: seat PATCH assign $case->[0]",
                "Invalid 'alias_numbers', not available in the PBX pool: " . number_as_string($number->($case->[1])));
        }
        ok(!$number_exists->('95'), 'subscriberadmin: new number not created');
        is_deeply($aliases->($seat_u->{id}), $numbers->('82'), 'subscriberadmin: other seat keeps its number');
        is_deeply($aliases->($seat_t->{id}), $numbers->(qw/81 91/), 'subscriberadmin: seat aliases unchanged after rejects');

        my $seat_put = $own_get->($seat_t->{id});
        delete $seat_put->{alias_numbers};
        $put_state_ok->($seat_t->{id}, { %{$seat_put}, display_name => 'Seat T PUT' },
            'subscriberadmin: seat PUT without alias_numbers revokes them', display_name => 'Seat T PUT', aliases => []);
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/81 91 92 93 94/), 'subscriberadmin: PUT revoked numbers are in the pool');
        $put_state_ok->($seat_t->{id}, { %{$seat_put}, display_name => 'Seat T PUT', alias_numbers => [ $number->('81'), $number->('92') ] },
            'subscriberadmin: seat PUT assign + revoke', aliases => $numbers->(qw/81 92/));
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/91 93 94/), 'subscriberadmin: 91 revoked to the pool, 92 taken');
        $patch_state_ok->($seat_t->{id}, [ { op => 'replace', path => '/alias_numbers', value => [] } ],
            'subscriberadmin: seat PATCH revoke all', aliases => []);
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/81 91 92 93 94/), 'subscriberadmin: revoked numbers are in the pool');

        my $new_seat = sub {
            my ($name, $extension, @aliases) = @_;
            return $user->request_post({
                customer_id   => $customer{pbxaccount},
                domain        => $domain,
                username      => "restricted_${name}_$ts",
                webusername   => "restricted_${name}_$ts",
                password      => $password,
                webpassword   => $password,
                pbx_extension => $extension,
                alias_numbers => [ map { $number->($_) } @aliases ],
            }, '/api/subscribers/');
        };
        ($res, $content) = $user->request_post({
            customer_id    => $customer{pbxaccount},
            domain         => $domain,
            username       => "restricted_seat_adm_$ts",
            password       => $password,
            pbx_extension  => '13',
            administrative => JSON::true,
        }, '/api/subscribers/');
        $code_ok->($res, $content, 422, 'subscriberadmin: POST administrative seat');
        is($content->{message}, $readonly_message->('administrative'), 'subscriberadmin: POST administrative seat: message');
        ($res, $content) = $as_admin->()->request_get("/api/subscribers/?username=restricted_seat_adm_$ts");
        is($content->{total_count}, 0, 'subscriberadmin: administrative seat not created');
        ($res, $content) = $new_seat->('seat_v', '16', '93');
        $code_ok->($res, $content, 201, 'subscriberadmin: POST seat with pool number');
        my $seat_v_id = $created_id->($res);
        is_deeply($aliases->($seat_v_id), $numbers->('93'), 'subscriberadmin: new seat got the pool number');
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/81 91 92 94/), 'subscriberadmin: pool number moved to the new seat');
        for my $case ([ 'new number', 'seat_w', '17', '96' ], [ 'number of other seat', 'seat_x', '18', '82' ]) {
            my ($name, $username, $extension, $n) = @{$case};
            ($res, $content) = $new_seat->($username, $extension, $n);
            $code_ok->($res, $content, 422, "subscriberadmin: POST seat with $name",
                "Invalid 'alias_numbers', not available in the PBX pool: " . number_as_string($number->($n)));
            ($res, $content) = $as_admin->()->request_get("/api/subscribers/?username=restricted_${username}_$ts");
            is($content->{total_count}, 0, "subscriberadmin: seat with $name not created");
        }
        ok(!$number_exists->('96'), 'subscriberadmin: new number not created on POST');
        ($res, $content) = $patch->($seat_v_id, [ { op => 'replace', path => '/status', value => 'terminated' } ]);
        $code_ok->($res, $content, 200, 'subscriberadmin: seat PATCH status terminated');
        ($res) = $as_admin->()->request_get("/api/subscribers/$seat_v_id");
        is($res->code, 404, 'subscriberadmin: terminated seat is gone');
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/81 91 92 93 94/), 'subscriberadmin: terminated seat numbers back in the pool');

        #---- pilot (subscriberadmin) as the actor
        $login->($pilot);
        $visibility_ok->($pilot->{id}, 'pilot: own GET');
        $rejected_cases->($pilot->{id}, 'pilot: own', $cases->('status locked', 'remove alias', 'lock 4', 'administrative off'));
        $patch_state_ok->($seat_u->{id}, [ { op => 'add', path => '/alias_numbers/-', value => $number->('94') } ],
            'pilot: seat PATCH assign pool number', aliases => $numbers->(qw/82 94/));
        is_deeply($aliases->($pilot->{id}), $numbers->(qw/81 91 92 93/), 'pilot: pool number moved');

        #---- admin is not restricted (PBX)
        ($res, $content) = $admin_patch->($pilot->{id}, [ { op => 'add', path => '/alias_numbers/-', value => $number->('99') } ]);
        $code_ok->($res, $content, 200, 'admin: PATCH pilot alias_numbers');
        ($res, $content) = $admin_patch->($seat_u->{id}, [ { op => 'replace', path => '/status', value => 'locked' } ]);
        $code_ok->($res, $content, 200, 'admin: PATCH seat status');

        for my $id ($group->{id}, $seat_t->{id}, $seat_u->{id}, $subadmin->{id}, $pilot->{id}) {
            $as_admin->()->request_delete("/api/subscribers/$id");
        }
    }

    for my $id ($sip_other->{id}, $sip_admin->{id}, $sip->{id}) {
        $as_admin->()->request_delete("/api/subscribers/$id");
    }
    $as_admin->()->request_delete("/api/subscriberprofiles/$profile_id");
    $as_admin->()->request_delete("/api/subscriberprofilesets/$profile_set_id");
    $admin_cert->($test_machine);
}

$test_machine->init_ssl_cert();
$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
$fake_data->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;


#--------- aux
sub check_password_validation_config{
    if(
        $remote_config->{config}->{security}->{password_sip_validate}
        &&
        $remote_config->{config}->{security}->{password_web_validate}
        &&
        ok($remote_config->{config}->{security}->{password_sip_validate},"check www_admin.security.password_sip_validate should be true.")
        &&
        ok($remote_config->{config}->{security}->{password_web_validate},"check www_admin.security.password_web_validate should be true.")) {
        return 1;
    }
    return 0;
}

sub test_password_validation {
    my ($subscriber_put, $actions) = @_;
    my %fields = ('web' => 'web%s','' => '%s');
    my $data_pre = clone $subscriber_put->{content};
    my $uri = $subscriber_put->{location};
    $data_pre->{password} = 'not empty 1';#to don't raise error for empty pass when checking webpass
    #print Dumper $data_pre;
    foreach my $type ('','web'){
        my $fieldformat = $fields{$type};
        my $usernamefield = sprintf($fieldformat,'username');
        my $passwordfield = sprintf($fieldformat,'password');
        my $message_start = ($type ? ucfirst($type)." password" : "Password");

        #test POST
        if(!$actions || $actions->{POST}){
            my $data = clone $data_pre;
            $data->{$usernamefield} .= '_post_lc';
            $data->{$passwordfield} = ' '.ucfirst($data->{$usernamefield}).' ';
            my($res,$content) = $test_machine->request_post($data);
            $test_machine->http_code_msg(422, $message_start." must not contain username", $res, $content, 1);

            $data = clone $data_pre;
            $data->{$usernamefield} .= '_post1';
            $data->{$passwordfield} = '123456';
            ($res,$content) = $test_machine->request_post($data);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);

            $data = clone $data_pre;
            $data->{$usernamefield} .= '_post2';
            $data->{$passwordfield} = 'qwerty';
            ($res,$content) = $test_machine->request_post($data);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);

            $data = clone $data_pre;
            $data->{$usernamefield} .= '_post3';
            $data->{$passwordfield} = 'passwd';
            ($res,$content) = $test_machine->request_post($data);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);
        }
        if(!$actions || $actions->{PUT}){
            #test PUT
            my $data = clone $data_pre;
            $data = $subscriber_put->{content};
            $data->{$usernamefield} .= '_put_lc';
            $data->{$passwordfield} = ' '.ucfirst($data->{$usernamefield}).' ';
            my($res,$content) = $test_machine->request_put($data,$uri);
            $test_machine->http_code_msg(422, $message_start." must not contain username", $res, $content, 1);

            $data = clone $data_pre;
            $data->{$usernamefield} .= '_put1';
            $data->{$passwordfield} = '123abc';
            ($res,$content) = $test_machine->request_put($data,$uri);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);

            $data = clone $data_pre;
            $data->{$usernamefield} .= '_put2';
            $data->{$passwordfield} = 'something';
            ($res,$content) = $test_machine->request_put($data,$uri);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);

            $data = clone $data_pre;
            $data->{$usernamefield} .= '_put3';
            $data->{$passwordfield} = 'password';
            ($res,$content) = $test_machine->request_put($data,$uri);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);
        }
        if(!$actions || $actions->{PATCH}){
            #test PATCH
            my $data = clone $data_pre;
            my $username = $data->{$usernamefield}.= '_patch_lc';
            my $password = ' '.ucfirst($username).' ';
            my($res,$content) = $test_machine->request_patch(
                [
                    { op => 'replace', path => '/'.$usernamefield, value => $username},
                    { op => 'replace', path => '/'.$passwordfield, value => $password},
                ],
                $uri);
            $test_machine->http_code_msg(422, $message_start." must not contain username", $res, $content, 1);

            $data = clone $data_pre;
            $username = $data->{$usernamefield}.= '_patch1';
            $password = '12345678';
            ($res,$content) = $test_machine->request_patch(
                [
                    { op => 'replace', path => '/'.$usernamefield, value => $username},
                    { op => 'replace', path => '/'.$passwordfield, value => $password},
                ],
                $uri);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);

            $data = clone $data_pre;
            $username = $data->{$usernamefield}.= '_patch2';
            $password = '111aaa';
            ($res,$content) = $test_machine->request_patch(
                [
                    { op => 'replace', path => '/'.$usernamefield, value => $username},
                    { op => 'replace', path => '/'.$passwordfield, value => $password},
                ],
                $uri);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);

            $data = clone $data_pre;
            $username = $data->{$usernamefield}.= '_patch3';
            $password = 'mypassword';
            ($res,$content) = $test_machine->request_patch(
                [
                    { op => 'replace', path => '/'.$usernamefield, value => $username},
                    { op => 'replace', path => '/'.$passwordfield, value => $password},
                ],
                $uri);
            $test_machine->http_code_msg(422, $message_start." is too weak", $res, $content, 1);
        }
    }
}

sub create_subs_and_subadmin {
    my ($fake_data_l, $test_machine_l, $prefix, $no_pilot) = @_;

    $prefix //= '';

    my $fake_data_l_processed = $fake_data_l->process('subscribers');
    #print Dumper ['create_subs_and_subadmin','fake_data_l_processed',$fake_data_l_processed];
    $test_machine_l->DATA_ITEM($fake_data_l_processed);
    $test_machine_l->DATA_ITEM_STORE($fake_data_l_processed);

    my $pilot_l = $test_machine_l->get_item_hal('subscribers','/api/subscribers/?customer_id='.$fake_data_l_processed->{customer_id}.'&'.'is_pbx_pilot=1');
    if((exists $pilot_l->{total_count} && $pilot_l->{total_count}) || (exists $pilot_l->{content}->{total_count} && $pilot_l->{content}->{total_count} > 0)){
        #remove existing pilot aliases to don't intersect with them. On subscriber termination admin adopt numbers, see ticket#4967
        my($res, $mod_pilot) = $test_machine_l->request_patch([
                { op => 'replace', path => '/alias_numbers', value => [] },
                #to don't intersect with manual testing on the web
                { op => 'replace', path => '/profile_set_id', value => $fake_data_l->get_id('subscriberprofilesets') },
                { op => 'replace', path => '/profile_id', value => undef },#we will take default profile for profile_set
                #we can't change domain
                #and we can create subscriber in domain out of reseller
                #{ op => 'replace', path => '/domain_id', value => $fake_data_l->get_id('domains') },
            ],
            $pilot_l->{location} );
            #print Dumper $pilot_l->{content};
            #print Dumper $res;
    }else{
        undef $pilot_l;
    }

    my $subscribers = $test_machine_l->check_create_correct(3, sub {
        my $num = $_[1]->{i};
        my $uniq = Test::FakeData::seq;
        $_[0]->{webusername} = '43350_'.$uniq.'_'.$prefix;
        $_[0]->{username} = '43350_'.$uniq.'_'.$prefix ;
        $_[0]->{pbx_extension} = '43350'.$uniq;
        $_[0]->{primary_number}->{ac} = '43350'.$uniq;
        $_[0]->{is_pbx_pilot} = ($pilot_l || $num > 1 )? 0 : 1;
        $_[0]->{administrative} = 0;
        $_[0]->{alias_numbers} = [{
            ac => '43350'.$uniq,
            cc => $uniq,
            sn => '43350'.$uniq,
        }];
        #$_[0]->{domain} = $pilot_l->{domain};
        $pilot_l and $_[0]->{domain_id} = $pilot_l->{content}->{domain_id};
    });

    #$fake_data_l->get_id('resellers',@_);
    diag("#------------------------ create subscriberadmin\n");
    my $subscriberadmins = $test_machine_l->check_create_correct(1, sub {
        my $num = $_[1]->{i};
        my $uniq = Test::FakeData::seq;
        $_[0]->{webusername} = '43350_'.$uniq.'_'.$prefix.'_adm';
        $_[0]->{username} = '43350_'.$uniq.'_'.$prefix.'_adm';
        $_[0]->{pbx_extension} = '43350'.$uniq;
        $_[0]->{primary_number}->{ac} = '43350'.$uniq;
        $_[0]->{administrative} = 1;
        $_[0]->{is_pbx_pilot} = 0;
        delete $_[0]->{alias_numbers};
    });
        diag("#------------------------ /create subscriberadmin\n");
    return $subscribers, $subscriberadmins;
}

sub number_as_string{
    my ($number_row, %params) = @_;
    return 'HASH' eq ref $number_row
        ? $number_row->{cc} . ($number_row->{ac} // '') . $number_row->{sn}
        : $number_row->cc . ($number_row->ac // '') . $number_row->sn;
}

# vim: set tabstop=4 expandtab:
