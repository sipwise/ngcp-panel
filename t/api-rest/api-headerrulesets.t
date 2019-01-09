use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'headerrulesets',
    embedded_resources => []
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    headerrulesets => {
        'data' => {
            reseller_id     => sub { return shift->get_id('resellers',@_); },
            name            => 'api_test',
            description     => 'api_test rule set description',
        },
        'query' => ['name'],
        'data_callbacks' => {
            'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{name}); },
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('headerrulesets'));

$test_machine->form_data_item( );
my $sets = $test_machine->check_create_correct( 3, sub{ $_[0]->{name} .=  $_[1]->{i}.time(); } );
$test_machine->check_get2put();
$test_machine->check_bundle();

# try to create ruleset without reseller_id
{
    my ($res, $err) = $test_machine->check_item_post(sub{delete $_[0]->{reseller_id};});
    is($res->code, 422, "create ruleset without reseller_id");
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
}


$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
