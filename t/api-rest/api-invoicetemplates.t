use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'invoicetemplates',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET OPTIONS HEAD)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET OPTIONS HEAD)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    invoicetemplates => {
        data => {
            'reseller_id'     =>  sub { return shift->get_id('resellers',@_); },
            'name'            => 'api_test invoice template name'.time(),
            'type'            => 'svg',
            'data'            => 'api_test email template',
        },
        'query' => ['name'],
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('invoicetemplates'));

$test_machine->form_data_item( );
# create 3 new sound sets from DATA_ITEM
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
