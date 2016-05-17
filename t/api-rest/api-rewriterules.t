use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'rewriterules',
    embedded_resources => [qw/rewriterulesets/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    rewriterules => {
        data => {
            set_id  =>  sub { return shift->get_id('rewriterulesets',@_); },
            match_pattern   => '^111$',
            replace_pattern => '222',
            description     => 'test_api rewrite rule',
            direction       => 'in',#out
            field           => 'caller',#calee
            priority        => '1',
            enabled         => '1',
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('rewriterules'));

$test_machine->form_data_item( );
# create 3 new field pbx devices from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{description} .=  $_[1]->{i}; } );
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;

# vim: set tabstop=4 expandtab:
