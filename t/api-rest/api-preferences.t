use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Clone qw/clone/;

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
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('preferences'));
$test_machine->form_data_item( );

my @apis = qw/subscriber domain peeringserver customer profile/;

foreach my $api (@apis){


    my $preferences_old;
    my $preferences_put;
    my ($preferences) = {'uri' => '/api/'.$api.'preferences/'.$test_machine->DATA_ITEM->{$api.'_id'}};
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
        if('boolean' eq $preference->{data_type}){
            $preferences->{content}->{$preference_name} = 1;
        }elsif('enum' eq $preference->{data_type}){
            my @values = @{$preference->{enum_values}};
            if(@values){
                if($#values > 0){
                #take second value from enum if exists
                    $preferences->{content}->{$preference_name} = @values[1];
                }
            }
            #foreach my $preference_enum_value(@{$preference->{enum_values}}){
            #    
            #}
        }elsif('string' eq $preference->{data_type}){
            $preferences->{content}->{$preference_name} = "test_api preference string";
        }elsif('int' eq $preference->{data_type}){
            $preferences->{content}->{$preference_name} = 33;
        }else{
            die("unknown data type: ".$preference->{data_type}." for $preference_name;\n");
        }
    }
    (undef, $preferences_put->{content}) = $test_machine->request_put($preferences->{content},$preferences->{uri});
    (undef, $preferences_put->{content}) = $test_machine->request_put($preferences_old,$preferences->{uri});
}
done_testing;

# vim: set tabstop=4 expandtab:
