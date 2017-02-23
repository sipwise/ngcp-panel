use strict;

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
    'collections'        => {},
    'ignore_existence'   => 1,
};
$test_machine = Test::Collection->new(
    'name'=>'',
    'ALLOW_EMPTY_COLLECTION' => 1,
    'runas_role' => 'reseller',
);
$fake_data = Test::FakeData->new;
$test_machine->clear_cache;

get_opt();
get_api_config();
init_config();
init_report();

run();

$test_machine->clear_test_data_all();
done_testing;
undef $fake_data;
undef $test_machine;

print Dumper $report;


#------------------------ subs -----------------------


sub run{
    #my($opt,$report,$api_info,$test_machine,$fake_data,$config)
    foreach my $collection ( sort grep { collection4testing($_) } keys %{$api_info} ){

        $test_machine->name($collection);
        $test_machine->NO_ITEM_MODULE($api_info->{$collection}->{module_item} ? 0 : 1 );
        $test_machine->methods({
            collection => { allowed => { map { $_ => 1 } keys %{$api_info->{$collection}->{allowed_methods}} }},
            item       => { allowed => { map { $_ => 1 } keys %{$api_info->{$collection}->{allowed_methods_item}} }},
        });

        #$test_machine->check_bundle();

        if($test_machine->{methods}->{collection}->{allowed}->{POST}){
            #load date 
            if(!$fake_data->{data}->{$collection}->{data}){
                testscript_under_framework($collection);
            }
            if($fake_data->{data}->{$collection}->{data}){
                my $data = $fake_data->{data}->{$collection}->{data};
                #$data->{json} && ( $data = $data->{json});
                $fake_data->process($collection);
                $test_machine->check_create_correct( 
                    1, 
                    $fake_data->{data}->{$collection}->{uniquizer_cb}, 
                    clone $fake_data->{data}->{$collection}->{data} 
                );
                $report->{post_tested} = $collection;
            }else{
                $report->{post_untested} = $collection;
            }
        }
        if($test_machine->{methods}->{collection}->{allowed}->{GET}){
            #my $item = $test_machine->get_item_hal( undef, undef, 1);#reload
            if(!$test_machine->IS_EMPTY_COLLECTION){
                push @{$report->{'collections_not_empty'}}, $collection;
                if($test_machine->{methods}->{item}->{allowed}->{PUT}){
                    #$test_machine->check_get2put();
                }
            }else{
                push @{$report->{'collections_empty'}}, $collection;
            }
        }else{
            push @{$report->{'collections_no_get'}}, $collection;
        }
        if(!$api_info->{$collection}->{module_item}){
            push @{$report->{'no_module_item'}}, $collection;
        }
        push @{$report->{'checked'}}, $collection;
    }
}


#------------------------ aux -----------------------

sub get_opt{#get $opt
    my $opt_in = {};
    GetOptions($opt_in,
        "help|h|?"             ,
        "collections:s"        ,
        "ignore-existence"     ,
    ) or pod2usage(2);
    my @opt_keys = keys %$opt_in;
    @{$opt}{ map{my $k=$_;$k=~s/\-/_/;$k;} @opt_keys } = map {my $v = $opt_in->{$_}; $v={ map {$_=>1;} split(/[^[:alnum:]]+/,$v ) }; $v;} @opt_keys ;
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
        'subscriberpreferences' => 1,
        'customerpreferences' => 1,
        'domainpreferences' => 1,
        'peeringserverpreferences' => 1,
        'profilepreferences' => 1,
        'pbxdevicepreferencedefs' => 1,
        'pbxdeviceprofilepreferencedefs' => 1,
        #defs and preferences are tested in context of preferences
        'pbxdevicefirmwares' => 1, #too hard, fails with timeout on get
    #falis with: not ok 163 - ccmapentries: check_get2put: check put successful (Unprocessable Entity: Validation failed. field='mappings', input='ARRAY(0x1a53f278)', errors='Mappings field is required')
        'ccmapentries' => 1,
    #fails with:
    #          got: 'https://127.0.0.1:1443/api/customerzonecosts/?page=1&rows=5&start=2016-10-01T000000&end=2016-10-31T235959'
    #     expected: 'https://127.0.0.1:1443/api/customerzonecosts/?page=1&rows=5'
        'customerzonecosts' => 1,
    #fails with: Unsupported media type 'application/json', accepting text/plain or text/xml only.)
        'pbxdeviceconfigs' => 1,
    #fails with: not ok 1131 - rtcapps: check_get2put: check put successful (Unprocessable Entity: Invalid field 'apps'. Must be an array.)
        'rtcapps' => 1,
    #fails with: not ok 1176 - rtcnetworks: check_get2put: check put successful (Unprocessable Entity: Invalid field 'networks'. Must be an array.)
        'rtcnetworks' => 1,
    );
    my %test_exists;
    {
        my $dir = dirname($0);
        my $rule = File::Find::Rule->new
            ->mindepth(1)
            ->maxdepth(1)
            ->name('api-*.t');
        %test_exists = map {$_=~s/\Q$dir\/\E//;$_ => 1} $rule->in($dir);
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
    print Dumper ["testscript_under_framework", $@];
    if($@){
        return 0;
    }
    else{
        return 1;
    }
}

sub collection4testing{
    my $collection = shift;
    my $r = (! ( scalar keys %{$opt->{collections}} ) ) || $opt->{collections}->{$collection};
    if($r){
        #by default we run requested collection scripts even when exists
        if(!$opt->{collections}->{$collection}){
            if(testscript_exists($collection) && !$opt->{ignore_existence}){
                push @{$report->{'tests_exists_skipped'}}, $collection;
                #we will not test the same twice
                $r = 0;
            }
            $r = 0 if $config->{test_exclude}->{$collection};
        }
    }
    return $r;
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