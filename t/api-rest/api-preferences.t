use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use JSON;
use Clone qw/clone/;
use feature "state";


#init test_machine
my $test_machine = Test::Collection->new(
    name => 'preferences',
);
my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    preferences => {
        data => {
            peeringserver_id  =>  sub { return shift->get_id('peeringservers',@_); },
            customer_id  =>  sub { return shift->get_id('customers',@_); },
            subscriber_id  =>  sub { return shift->get_id('subscribers',@_); },
            domain_id  =>  sub { return shift->get_id('domains',@_); },
            profile_id  =>  sub { return shift->get_id('subscriberprofiles',@_); },
            pbxdevice_id  =>  sub { return shift->get_id('pbxdevicemodels',@_); },
            pbxfielddevice_id  =>  sub { return shift->get_id('pbxdevices',@_); },
            pbxdeviceprofile_id  =>  sub { return shift->get_id('pbxdeviceprofiles',@_); },
            emergencymappingcontainer_id  =>  sub { return shift->get_id('emergencymappingcontainers',@_); },

            rewriteruleset_id  =>  sub { return shift->get_id('rewriterulesets',@_); },
            soundset_id  =>  sub { return shift->get_id('soundsets',@_); },
            ncoslevel_id  =>  sub { return shift->get_id('ncoslevels',@_); },
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('preferences'));
$test_machine->form_data_item( );

my @apis = qw/subscriber domain peeringserver customer profile pbxdevice pbxfielddevice pbxdeviceprofile/;
#my @apis = qw/pbxdevice/;

foreach my $api (@apis){
    my $preferences_old;
    my $preferences_put;
    my $preferences_patch;
    my $res;
    my $index = $api.'_id';
    my ($preferences) = {'uri' => '/api/'.$api.'preferences/'.$test_machine->DATA_ITEM->{$index}};
    (undef, $preferences_old) = $test_machine->check_item_get($preferences->{uri});
    #$preferences->{content} = $preferences_old;

    my $api_test_machine = Test::Collection->new(
        name => $api.'preferences',
    );
    $api_test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
    $api_test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};
    my $defs = $api_test_machine->get_item_hal($api.'preferencedefs');
    delete $defs->{content}->{_links};
    foreach my $preference_name(keys %{$defs->{content}}){
        my $preference = $defs->{content}->{$preference_name};
        $preference->{name} = $preference_name;
        #if($preference->{read_only}){
        #    next;
        #}
        my $value;
        if('boolean' eq $preference->{data_type}){
            $value = JSON::true;
        }elsif('enum' eq $preference->{data_type}){
            my @values = @{$preference->{enum_values}};
            if(@values){
                if($#values > 0){
                #take second value from enum if exists
                    $value = $values[1]->{value};
                }
            }
            #foreach my $preference_enum_value(@{$preference->{enum_values}}){
            #
            #}
        }elsif('string' eq $preference->{data_type}){
            $value = get_preference_existen_value($preference) // "test_api preference string";
        }elsif('int' eq $preference->{data_type}){
            $value = get_preference_existen_value($preference) // 33;
        }else{
            die("unknown data type: ".$preference->{data_type}." for $preference_name;\n");
        }
        if($value && 'no_process' ne $value){
            if($preference->{max_occur} > 0 ){
                if ($preference->{max_occur} eq '1') {
                    $preferences->{content}->{$preference_name} = $value;
                } else {
                    $preferences->{content}->{$preference_name} = [$value];
                }
            }
        }else{
            #print "Undefined value for preference: $api:$preference_name;\n";
            #print Dumper $preference;
        }
    }
    #(undef, $preferences_put->{content}) = $test_machine->request_put($preferences->{content},$preferences->{uri});
    #we don't check read_only flag when update preferences?
    (undef, $preferences_put->{content}) = $test_machine->check_put2get({data_in=>$preferences->{content},uri=>$preferences->{uri}},undef, { skip_compare => 1 });
    (undef, $preferences_patch->{content}) = $test_machine->check_patch2get({location => $preferences->{uri}} );

    if ($api eq 'subscriber') {
        diag("test extended patch");
        my $preferences_new;
        my $addmulti_value = ['111','222','222','333'];
        my $preferences_patch_op = [
            {'op' => 'add', 'path' => '/allowed_clis', value => $addmulti_value, mode => 'append' },
        ];
        ($res, $preferences_put->{content}) = $test_machine->request_patch($preferences_patch_op,$preferences->{uri});
        $test_machine->http_code_msg(200, "check extended patch result: add multi to absent", $res, $preferences_put->{content});
        (undef, $preferences_new->{content}) = $test_machine->check_item_get($preferences->{uri});
        is_deeply([@{$preferences_new->{content}->{allowed_clis}}[-4..-1]], $addmulti_value, "check patched allowed_clis: add multi to absent");

        $addmulti_value = ['222','222','222','555','666'];
        $preferences_patch_op = [
            {'op' => 'add', 'path' => '/allowed_clis', value => $addmulti_value, mode => 'append' },
        ];
        ($res, $preferences_put->{content}) = $test_machine->request_patch($preferences_patch_op,$preferences->{uri});
        $test_machine->http_code_msg(200, "check extended patch result: add multi to existing", $res, $preferences_put->{content});
        (undef, $preferences_new->{content}) = $test_machine->check_item_get($preferences->{uri});
        is_deeply([@{$preferences_new->{content}->{allowed_clis}}[-5..-1]], $addmulti_value, "check patched allowed_clis: add multi to existing");

        $preferences_patch_op = [
            {'op' => 'remove', 'path' => '/allowed_clis', value => '222', 'index' => 2 },
        ];
        ($res, $preferences_put->{content}) = $test_machine->request_patch($preferences_patch_op,$preferences->{uri});
        $test_machine->http_code_msg(200, "check extended patch result: remove by value", $res, $preferences_put->{content});
        (undef, $preferences_new->{content}) = $test_machine->check_item_get($preferences->{uri});
        is_deeply([@{$preferences_new->{content}->{allowed_clis}}[-8..-1]], ['111','222','222','333','222','222','555','666'], "check patched allowed_clis: remove by value.");
    }


    ($res, $preferences_put->{content}) = $test_machine->request_put($preferences_old,$preferences->{uri});
    $test_machine->http_code_msg(200, "check return old values", $res, $preferences_put->{content});
}

$test_machine->clear_test_data_all();
undef $fake_data;
undef $test_machine;
done_testing;

#----------------- aux
sub get_preference_existen_value{
    my $preference = shift;
    my $res;
    if($preference->{name}=~/^rewrite_rule_set$/){
        $res = get_fake_data_created_or_data('rewriterulesets','name');
    }elsif($preference->{name}=~/^(adm_)?(cf_)?ncos$/){
        $res = get_fake_data_created_or_data('ncoslevels','level');
    }elsif($preference->{name}=~/^(contract_)?sound_set$/){
        $res = get_fake_data_created_or_data('soundsets','name');
    }elsif($preference->{name}=~/^emergency_mapping_container$/){
        $res = get_fake_data_created_or_data('emergencymappingcontainers','name');
    }elsif($preference->{name}=~/^(man_)?allowed_ips_grp$/){
        $res = 'no_process';
    }
    return $res;
}

sub get_fake_data_created_or_data{
    my($collection_name, $field, $number) = @_;
    $number //= 0;
    my $res = $fake_data->created->{$collection_name}
        ?
        $fake_data->created->{$collection_name}->{values}->[$number]->{content}->{$field}
        :
        $fake_data->{data}->{$collection_name}->{data}->{$field};
    return $res;
}

__DATA__

'lbrtp_set' => {
    'enum_values' => [
        {
            'value' => undef,
            'default_val' => $VAR1->{'mobile_push_expiry'}{'read_only'},
            'label' => 'None'
        },
        {
            'value' => '50',
            'default_val' => $VAR1->{'mobile_push_expiry'}{'read_only'},
            'label' => 'default'
        }
    ],
    'data_type' => 'enum',
    'read_only' => $VAR1->{'mobile_push_expiry'}{'read_only'},
    'max_occur' => 1,
    'label' => 'The cluster set used for SIP lb and RTP',
    'description' => 'Use a particular cluster set of load-balancers for SIP towards this endpoint (only for peers, as for subscribers it is defined by Path during registration) and of RTP relays (both peers and subscribers).'
},

# vim: set tabstop=4 expandtab:
