use strict;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Getopt::Long;
use File::Find::Rule;
use File::Basename;
use Clone qw/clone/;

my $opt = {
    'collections'        => {},
};
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


my $test_machine = Test::Collection->new('name'=>'','ALLOW_EMPTY_COLLECTION' => 1);
my $fake_data = Test::FakeData->new;
$test_machine->clear_cache;
my $remote_config = $test_machine->init_catalyst_config;
print Dumper $remote_config ;
my $data = $remote_config->{meta}->{'collections'};


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
    'pbxdevicefirmwares' => 1, #too hard
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

my $res = {
    'collections_no_get'    => [],
    'collections_empty'     => [],
    'collections_not_empty' => [],
    'strange_item_actions'  => {},
    'no_module_item'        => [],
    'tests_exists'          => \%test_exists,
    'tests_exists_skipped'  => [],
    'checked'               => [],
    'tests_exclude'         => \%test_exclude,
    'opt'                   => $opt
};
foreach my $collection ( sort grep{(! ( scalar keys $opt->{collections} ) ) || $opt->{collections}->{$_} } keys %{$data} ){
    if(!$opt->{collections}->{$collection}){
        if($test_exists{'api-'.$collection.'.t'} && !$opt->{ignore_existence}){
            push @{$res->{'tests_exists_skipped'}}, $collection;
            #we will not test the same twice
            next;
        }
        next if $test_exclude{$collection};
    }

    #print Dumper $data->{$collection}->{allowed_methods_item};
    #print Dumper $collection;

    my $item_allowed_actions = { allowed => {} };
    if($data->{$collection}->{module_item}){
        if(ref $data->{$collection}->{allowed_methods_item} eq 'HASH'){
            $item_allowed_actions = { allowed => { map { $_ => 1 } keys %{$data->{$collection}->{allowed_methods_item}} }};
        }else{
            $res->{'strange_item_actions'}->{$collection} = $data->{$collection}->{allowed_methods_item};
        }
    }else{
        push @{$res->{'no_module_item'}}, $collection;
    }
    push @{$res->{'checked'}}, $collection;
    $test_machine->name($collection);
    $test_machine->NO_ITEM_MODULE($data->{$collection}->{module_item} ? 0 : 1 );
    {
        $test_machine->methods({
            collection => { allowed => { map { $_ => 1 } keys %{$data->{$collection}->{allowed_methods}} }},
            item       =>  $item_allowed_actions,
        });
    }

    $test_machine->check_bundle();
    if($test_machine->{methods}->{collection}->{allowed}->{GET}){
        my $item = $test_machine->get_item_hal();
        #if($item->{content}->{total_count}){
        if(!$test_machine->IS_EMPTY_COLLECTION){
            push @{$res->{'collections_not_empty'}}, $collection;
            if($data->{$collection}->{allowed_methods}->{POST}){
                my $item_post = clone($item);
                delete $item_post->{content}->{id};
                $test_machine->DATA_ITEM_STORE($item_post->{content});
                $test_machine->form_data_item();
                #test_machine->check_create_correct( 1 );
            }
            if($test_machine->{methods}->{item}->{allowed}->{PUT}){
                $test_machine->check_get2put();
            }
        }else{
            push @{$res->{'collections_empty'}}, $collection;
        }
    }else{
        push @{$res->{'collections_no_get'}}, $collection;
    }
}

$test_machine->clear_test_data_all();
done_testing;

undef $fake_data;
undef $test_machine;

print Dumper $res;
# vim: set tabstop=4 expandtab: