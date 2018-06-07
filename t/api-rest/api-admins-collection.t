use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'admins',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS DELETE)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    'admins' => {
        'data' => {
            "reseller_id"  =>  sub { return shift->get_id('resellers',@_); },
            "login"     => 'api_test_admin',
            "password"  => 'api_test_admin',
            "is_active" => 'true',
            "is_master" => 'true',
            "is_superuser" => 'true',
            "billing_data" => 'true',
            "call_data" => 'false',
            "lawful_intercept" => 'false',
            "read_only" => 'false',
            "show_passwords" => 'true'
        },
        'query' => ['login'],
        'data_callbacks' => {
            'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{login}); },
        },
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('admins'));

$test_machine->form_data_item( );
# create 3 new admins from DATA_ITEM
my $admins = $test_machine->check_create_correct( 2 , sub {
    $_[0]->{login}.=time().seq()
});
ok($admins->[0]->{content}->{is_active},"Check if newly created admin is active");
my $admins2 = $test_machine->check_create_correct( 2 , sub {
    $_[0]->{login}.=time().seq();
    print "login=".$_[0]->{login}.";";
    foreach my $field(qw/is_active is_master is_superuser billing_data call_data lawful_intercept read_only show_passwords/) {
        $_[0]->{$field} = $_[0]->{$field} eq 'true' ? '1' : '0';
    }
});
ok($admins2->[0]->{content}->{is_active},"Check if newly created admin is active");

$test_machine->check_bundle();
$test_machine->clear_test_data_all();

done_testing;

# vim: set tabstop=4 expandtab:
