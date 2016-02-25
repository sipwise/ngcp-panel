use strict;

use lib '/root/VMHost/ngcp-panel/lib/';


use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

use NGCP::Panel::Utils::API;
use File::Find::Rule;

my $test_machine = Test::Collection->new('name'=>'','ALLOW_EMPTY_COLLECTION' => 1);
my $fake_data = Test::FakeData->new;
my $remote_config = $test_machine->init_catalyst_config;

my %test_exclude = (
    'subscriberpreferencedefs' => 1,
    'metaconfigdefs' => 1,
    'customerpreferencedefs' => 1,
    'domainpreferencedefs' => 1,
    'peeringserverpreferencedefs' => 1,
    'profilepreferencedefs' => 1,
    'subscriberpreferences' => 1,
    'customerpreferences' => 1,
    'domainpreferences' => 1,
    'peeringserverpreferences' => 1,
    'profilepreferences' => 1,
    #defs and preferences are tested in context of preferences
);
my %test_exists; 
{
    my $rule = File::Find::Rule->new
        ->mindepth(1)
        ->maxdepth(1)
        ->name('api-*.t');
    %test_exists = map {$_ => 1} $rule->in($0);
    print Dumper \%test_exists;
}

my $res = {'collections_no_get'=>[],strange_item_actions => {}};

my $data = $remote_config->{meta}->{'collections'};
foreach my $collection ( keys %{$data} ){
    next if $test_exists{'api-'.$collection.'.t'};#we will not test the same twice
    next if $test_exclude{$collection};#we will not test the same twice
    next if $data->{$collection}->{module} =~/Defs$/;
    #print Dumper $data->{$collection}->{item_allowed_methods};
    #print Dumper $collection;


    my $item_allowed_actions;
    if(ref $data->{$collection}->{item_allowed_methods} eq 'HASH'){
        $item_allowed_actions = { allowed => { map { $_ => 1 } keys %{$data->{$collection}->{item_allowed_methods}} }};
    }else{
        $item_allowed_actions = {};
        $res->{'strange_item_actions'}->{$collection} = $data->{$collection}->{item_allowed_methods};
    }
    $test_machine->name($collection);
    {
        $test_machine->methods({
            collection => { allowed => { map { $_ => 1 } keys %{$data->{$collection}->{allowed_methods}} }},
            item       =>  $item_allowed_actions,
        });
    }
    $test_machine->check_bundle();
#    if ($data->{$collection}->{module} !~/Defs$/){
    if($test_machine->{methods}->{collection}->{allowed}->{GET}){
        my $item = $test_machine->get_item_hal();
        if($item->{content}->{total_count}){
            if($data->{$collection}->{allowed_methods}->{POST}){
                $test_machine->DATA_ITEM_STORE($item->{content});
                $test_machine->form_data_item();
                #test_machine->check_create_correct( 1 );
            }
            if($test_machine->{methods}->{item}->{allowed}->{PUT}){
                $test_machine->check_get2put();
            }
        }
    }else{
        push @{$res->{'collections_no_get'}}, $collection;
    }
        #$fake_data->set_data_from_script({
        #    $collection => {
        #        'data' => {
        #        },
        #        #'query' => ['username'],
        #    },
        #});

        #$test_machine->DATA_ITEM_STORE($fake_data->process($collection));
        #$test_machine->form_data_item( );
        
        #test_machine->check_create_correct( 1, sub{ $_[0]->{username} .= time().'_'.$_[1]->{i} ; } );
        #$test_machine->check_bundle();
        ##$test_machine->check_get2put();
        #   my $collections_no_get = [
        #                            'applyrewrites',
        #                            'faxrecordings',
        #                            'topupcash',
        #                            'soundfilerecordings',
        #                            'voicemailrecordings',
        #                            'pbxdevicemodelimages',
        #                            'callcontrols',
        #                            'pbxdeviceconfigfiles',
        #                            'topupvouchers',
        #                            'pbxdevicefirmwarebinaries'
        #                          ];
#   }else{
 #       #check get here
 #   }
}

print Dumper $res;

$test_machine->clear_test_data_all();
done_testing;


undef $fake_data;
undef $test_machine;

# vim: set tabstop=4 expandtab:
