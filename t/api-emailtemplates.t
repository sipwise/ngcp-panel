use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'emailtemplates',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    emailtemplates => {
        data => {
            reseller_id      =>  sub { return shift->get_id('resellers',@_); },
            name             => 'api_test_email_template_name',
            from_email       => 'api_test@api-test.emal.com',
            subject          => 'api_test email template',
            body             => 'api_test email template: a lot of the text here',#0
        },
        'query' => ['name'],
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('emailtemplates'));

$test_machine->form_data_item( );
# create 3 new sound sets from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{name} .=  $_[1]->{i}; } );
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
