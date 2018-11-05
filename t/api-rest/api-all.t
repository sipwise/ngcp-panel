use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Getopt::Long;
use File::Find::Rule;
use File::Basename;
use Clone qw/clone/;

my($opt,$report,$api_config,$api_info,$config,$test_machine,$fake_data) = 
    ({},{},{},{} );

$opt = {
    'collections'      => {'billingzones' => 1,},
    'collections'      => {},
    'ignore_existence' => 1,
    'test_groups'      => { 
        get2put   => 1, 
        patch2get => 1, 
        post      => 1, 
        get       => 1, 
        bundle    => 1,
    },#post,get2put,get2patch,bundle
    #'test_groups'      => { post => 1 },#post,get2put,get2patch,bundle
};

$test_machine = Test::Collection->new(
    name                   => '',
    ALLOW_EMPTY_COLLECTION => 1,
    QUIET_DELETION         => 0,
    CHECK_LIST_LIMIT       => 3,
    runas_role             => 'admin',
);
$fake_data = Test::FakeData->new;
$fake_data->test_machine->QUIET_DELETION(0);
$fake_data->test_machine->KEEP_CREATED(0);
$test_machine->clear_cache;

get_opt();
get_api_config();
init_config();
init_report();

run();

$test_machine->clear_test_data_all();
undef $fake_data;

$test_machine->print_statistic;
undef $test_machine;
print Dumper $report;
done_testing;


#------------------------ subs -----------------------


sub run{
    #my($opt,$report,$api_info,$test_machine,$fake_data,$config)
    foreach my $collection ( sort grep { collection4testing($_) ? 1 : () } keys %{$api_info} ){
        $test_machine->name($collection);
        $test_machine->NO_ITEM_MODULE($api_info->{$collection}->{module_item} ? 0 : 1 );
        $test_machine->methods({
            collection => { allowed => { map { $_ => 1 } keys %{$api_info->{$collection}->{allowed_methods}} }},
            item       => { allowed => { map { $_ => 1 } keys %{$api_info->{$collection}->{allowed_methods_item}} }},
        });

        if(!$fake_data->{data}->{$collection}->{data}){
            testscript_under_framework($collection);
        }
        print "collection: $collection;\n";
        if($opt->{test_groups}->{post}){
            if($test_machine->{methods}->{collection}->{allowed}->{POST}){
                print "collection: $collection: post;\n";
                #load date 
                if($fake_data->{data}->{$collection}->{data}){
                    my $data = $fake_data->{data}->{$collection}->{data};
                    $fake_data->process($collection);
                    $fake_data->create($collection);
                    push @{$report->{post_tested}}, $collection;
                }else{
                    push @{$report->{post_untested}}, $collection;
                }
            }
        }
        if($opt->{test_groups}->{bundle}){
            @{$test_machine->content_type}{qw/POST PUT/}    = (
                $api_info->{$collection}->{allowed_methods}->{POST}->{ContentType}->[0] || 'application/json',
                $api_info->{$collection}->{allowed_methods_item}->{PUT}->{ContentType}>[0] || 'application/json',
            );
            $test_machine->check_bundle();
        }
        if($opt->{test_groups}->{get}){
            if($test_machine->{methods}->{collection}->{allowed}->{GET}){
                my $item = $test_machine->get_item_hal( undef, undef, 1);#reload
            }
        }
        if($opt->{test_groups}->{get2put}){
            print "collection: $collection: get2put;\n";
            #$test_machine->DATA_ITEM_STORE($fake_data->process($collection));
            if($test_machine->{methods}->{collection}->{allowed}->{GET}){
                my $item = $test_machine->get_item_hal( undef, undef, 1);#reload
                if(!$test_machine->IS_EMPTY_COLLECTION){
                    if($test_machine->{methods}->{item}->{allowed}->{PUT}){
                        my $ignore_fields_parameter = $fake_data->{data}->{$collection}->{update_change_fields};
                        my $params = {
                            $ignore_fields_parameter ? (ignore_fields => $ignore_fields_parameter): (),
                        };
                        $test_machine->check_get2put( {
                                data_cb => $fake_data->{data}->{$collection}->{data_callbacks}->{get2put},
                            }, { 
                                uri => $item->{location} ,
                            }, $params );
                    }
                }
            }
        }
        if($opt->{test_groups}->{patch2get}){
            print "collection: $collection: patch2get;\n";
            #$test_machine->DATA_ITEM_STORE($fake_data->process($collection));
            if($test_machine->{methods}->{collection}->{allowed}->{GET}){
                my $item = $test_machine->get_item_hal( undef, undef, 1);#reload
                if(!$test_machine->IS_EMPTY_COLLECTION){
                    if($test_machine->{methods}->{item}->{allowed}->{PATCH}){
                        my $ignore_fields_parameter = $fake_data->{data}->{$collection}->{update_change_fields};
                        my $patch_exclude_fields = $fake_data->{data}->{$collection}->{patch_exclude_fields};
                        my $params = {
                            $ignore_fields_parameter ? (ignore_fields => $ignore_fields_parameter): (),
                            $patch_exclude_fields ? (patch_exclude_fields => $patch_exclude_fields): (),
                        };
                        $test_machine->check_patch2get( {
                                data_cb => $fake_data->{data}->{$collection}->{data_callbacks}->{patch2get},
                            }, { 
                                uri => $item->{location} ,
                            }, $params );
                    }
                }
            }
        }
        $test_machine->clear_data_created;
        if(!$test_machine->{methods}->{collection}->{allowed}->{GET}){
            push @{$report->{'collections_no_get'}}, $collection;
        }
        if(!$api_info->{$collection}->{module_item}){
            push @{$report->{'no_module_item'}}, $collection;
        }
        if(!$test_machine->IS_EMPTY_COLLECTION){
            push @{$report->{'collections_not_empty'}}, $collection;
        }else{
            push @{$report->{'collections_empty'}}, $collection;
        }
        push @{$report->{'checked'}}, $collection;
    }
}


#------------------------ aux -----------------------

sub get_opt{#get $opt
    my $opt_in = {};
    GetOptions($opt_in,
        "help|h|?"        ,
        "collections:s"   ,
        "ignore-existence",
        "test-groups"     ,
    ) or pod2usage(2);
    my @opt_keys = keys %$opt_in;
    @{$opt}{ map{ s/\-/_/; } @opt_keys } = map {my $v = $opt_in->{$_}; $v={ map {$_=>1;} split(/[^[:alnum:]]+/,$v ) }; $v;} @opt_keys ;
    print Dumper $opt;
    pod2usage(1) if $opt->{help};
    pod2usage(1) unless( 1
    #    defined $opt->{collections} && defined $opt->{etc}
    );
}

sub get_api_config{#get api_config
    my $api_config = $test_machine->init_catalyst_config; 
    $api_info = $api_config->{meta}->{'collections'};
}

sub init_config{#init config 
    my %test_exclude = (
        'metaconfigdefs' => 1,
        'subscriberpreferencedefs' => 1,
        'customerpreferencedefs' => 1,
        'domainpreferencedefs' => 1,
        'peeringserverpreferencedefs' => 1,
        'profilepreferencedefs' => 1,
        'pbxdevicepreferencedefs' => 1,
        'pbxdeviceprofilepreferencedefs' => 1,
        'pbxfielddevicepreferencedefs' => 1,
        'subscriberpreferences' => 1,
        'customerpreferences' => 1,
        'domainpreferences' => 1,
        'peeringserverpreferences' => 1,
        'profilepreferences' => 1,
        'pbxdevicepreferences' => 1,
        'pbxdeviceprofilepreferences' => 1,
        #defs and preferences are tested in context of preferences
        'pbxdevicefirmwares' => 1, #too hard, fails with timeout on get
        'sipcaptures' => 1, #too hard, it is ebout every packet

    #falis with: not ok 163 - ccmapentries: check_get2put: check put successful (Unprocessable Entity: Validation failed. field='mappings', input='ARRAY(0x1a53f278)', errors='Mappings field is required')
        #'ccmapentries' => 1,
    #fails with:
    #          got: 'https://127.0.0.1:1443/api/customerzonecosts/?page=1&rows=5&start=2016-10-01T000000&end=2016-10-31T235959'
    #     expected: 'https://127.0.0.1:1443/api/customerzonecosts/?page=1&rows=5'
        #'customerzonecosts' => 1,
    #fails with: Unsupported media type 'application/json', accepting text/plain or text/xml only.)
        #'pbxdeviceconfigs' => 1,
    #fails with: not ok 1131 - rtcapps: check_get2put: check put successful (Unprocessable Entity: Invalid field 'apps'. Must be an array.)
        #'rtcapps' => 1,
    #fails with: not ok 1176 - rtcnetworks: check_get2put: check put successful (Unprocessable Entity: Invalid field 'networks'. Must be an array.)
        #'rtcnetworks' => 1,

#--------- interceptions:
# No intercept agents configured in ngcp_panel.conf, rejecting request
#--------- callcontrols:
#Jan  3 12:48:20 sp1 ngcp-panel: INFO: received from dispatcher: $VAR1 = [#012 2,#012 1,#012 '<?xml version="1.0"?>#015#012<methodResponse><fault>#015#012#011<value><struct><member><name>faultCode</name><value><i4>-1</i4></value></member><member><name>faultString</name><value>dial_auth_b2b: unknown method name</value></member></struct></value>#015#012</fault></methodResponse>#015#012'#012];
#Jan  3 12:48:20 sp1 ngcp-panel: ERROR: failed to dial out: failed to trigger dial-out at /media/sf_/VMHost/ngcp-panel/lib/NGCP/Panel/Utils/Sems.pm line 326, <$fh> line 1.
#Jan  3 12:48:20 sp1 ngcp-panel: ERROR: error 500 - Failed to create call.
    );
    my %test_exists;
    {
        my $dir = dirname($0);
        my $rule = File::Find::Rule->new
            ->mindepth(1)
            ->maxdepth(1)
            ->name('api-*.t');
        %test_exists = map { s/\Q$dir\/\E//r => 1} $rule->in($dir);
    }
    $config->{tests_exists} = \%test_exists;
    $config->{tests_exclude} = \%test_exclude;
}

sub testscript_exists{
    my $collection = shift;
    return $config->{tests_exists}->{'api-'.$collection.'.t'};
}

sub testscript_under_framework{
    my $collection = shift;
    eval{
        $fake_data->load_data_from_script($collection);
    };
    if($@){
        print Dumper ["testscript_under_framework", $@];
        return 0;
    }
    else{
        return 1;
    }
}

sub collection4testing{
    my ($collection,$method) = @_;
    $method //= '';
    #check if collection is among directly requested. If no particular collections were requested, then all are requested
    my $run_collection_test = (! ( scalar keys %{$opt->{collections}} ) ) || $opt->{collections}->{$collection};

    if($run_collection_test){
        #we run requested collection scripts even when exists or is excluded. So Now check for not requested
        if(! $opt->{collections}->{$collection}){
            if( $config->{tests_exclude}->{$collection} ){
                if($method && $method ne 'all'){
                    if ((
                            'HASH' eq ref $config->{tests_exclude}->{$collection}
                            && $config->{tests_exclude}->{$collection}->{$method}
                        )
                        ||
                        (
                            'ARRAY' eq ref $config->{tests_exclude}->{$collection}
                            && grep { $method eq $_} @{$config->{tests_exclude}->{$collection}}
                    )){
                        #method excluded
                        $run_collection_test = 0;
                    } else {
                        $run_collection_test = 1;                    
                    }
                } elsif (! ref $config->{tests_exclude}->{$collection}) {
                    $run_collection_test = 0 ;
                } else {
                    $run_collection_test = 1;
                }
            }elsif(testscript_exists($collection) && !$opt->{ignore_existence}){
                push @{$report->{'tests_exists_skipped'}}, $collection;
                #we will not test the same twice
                $run_collection_test = 0;
            }
        }
    }
    return $run_collection_test;
}

sub init_report{
    $report = {
        'collections_no_get'    => [],
        'collections_empty'     => [],
        'collections_not_empty' => [],
        'strange_item_actions'  => {},
        'no_module_item'        => [],
        'tests_exists_skipped'  => [],
        'checked'               => [],
        'post_tested'           => [],
        'post_untested'         => [],
        'opt'                   => $opt,
        'config'                => $config,
    };
}



#my $item_post = clone($item);
#delete $item_post->{content}->{id};
#$test_machine->DATA_ITEM_STORE($item_post->{content});
#$test_machine->form_data_item();
##$test_machine->check_create_correct( 1, undef,  );
   
# vim: set tabstop=4 expandtab: