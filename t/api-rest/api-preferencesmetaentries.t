use strict;
use warnings;

use Test::More;
use Test::Collection;
use Test::FakeData;
use Data::Dumper;

my $test_machine = Test::Collection->new(
    name => 'preferencesmetaentries',
    QUIET_DELETION => 1,
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'preferencesmetaentries' => {
        data => {
            label         => "Custom pbx device model preference",
            description   => "Custom pbx device model preference description",
            attribute     => "123123123123123api_test",
            fielddev_pref => 1,
            max_occur     => 1,
            data_type     => 'enum',
            autoprov_device_id => sub { return shift->get_id('pbxdevicemodels',@_); },
            dev_pref      => 1,
            enum => [
                {
                   label       =>  "api_test_enum1",
                   value       => 1,
                   default_val => 0,
                },
                {
                   label       =>  "api_test_enum2",
                   value       => 2,
                   default_val => 1,
                }
            ],
        },
        'query' => ['attribute'],
        'data_callbacks' => {
            'uniquizer_cb' => sub { 
                Test::FakeData::string_uniquizer(\$_[0]->{attribute});
            },
        },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('preferencesmetaentries'));
$test_machine->form_data_item( );

# create 3 new preferences from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{attribute} .= time().$_[1]->{i} ; } );
$test_machine->check_get2put();
$test_machine->check_bundle();


$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();
undef $fake_data;
undef $test_machine;
done_testing;

# vim: set tabstop=4 expandtab:
