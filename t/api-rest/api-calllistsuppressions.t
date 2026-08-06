use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'calllistsuppressions',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'calllistsuppressions' => {
        data => {
            domain    => 'apitest.example.org',
            direction => 'outgoing',
            pattern   => '^431',
            mode      => 'obfuscate',
            label     => 'apitest',
        },
        'query' => ['domain','direction','mode'],
        'data_callbacks' => {
            'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{domain}); },
        },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('calllistsuppressions'));
$test_machine->form_data_item( );

# create 3 new call list suppressions from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{pattern} .= $_[1]->{i} ; } );
$test_machine->check_get2put();
$test_machine->check_bundle();

# domain, direction and pattern have to be unique together
{
    my ($res, $err) = $test_machine->check_item_post(sub{ $_[0]->{pattern} .= 1; });
    is($res->code, 422, "create call list suppression with duplicate domain/direction/pattern");
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /must be unique/, "check error message in body");
}

# an empty domain means any domain, and it is also the default
{
    #the domain is what the uniquizer varies, so uniquize the pattern instead to
    #keep the domain/direction/pattern triple unique across runs
    my ($res, $content) = $test_machine->check_item_post(sub{
        delete $_[0]->{domain};
        Test::FakeData::string_uniquizer(\$_[0]->{pattern});
    });
    is($res->code, 201, "create call list suppression without domain");
    is($content->{domain}, '', "check domain defaults to an empty string");
    #request_delete instead of check_item_delete: this item was not registered
    #by check_create_correct, so EXPECTED_AMOUNT_CREATED must stay untouched
    $test_machine->request_delete($res->header('Location'));
}

$test_machine->clear_test_data_all();
done_testing;

# vim: set tabstop=4 expandtab:
