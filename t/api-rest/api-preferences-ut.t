use strict;
use warnings;

use lib qw(/root/VMHost/ngcp-panel/lib/);
use Data::Dumper;

use Test::Collection;
use Test::FakeData;
use Test::More;
use JSON;
use Clone qw/clone/;

use NGCP::Schema;
use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Generic qw(:all);
use Safe::Isa qw($_isa);
use Test::MockObject;
Log::Log4perl::init('/etc/ngcp-panel/logging.conf');
use Log::Log4perl;

#prepare mock
my $logger = Log::Log4perl->get_logger('NGCP::Panel');
my $schema = NGCP::Schema->connect();
my $dbh = $schema->storage->dbh;

my $c_mock = Test::MockObject->new();
my $user_mock = Test::MockObject->new();
$user_mock->set_always( 'roles' => 'admin' );
$c_mock->set_always( 'log' => $logger )->set_always( 'model' => $schema )->set_always( 'user' => $user_mock );

use NGCP::Panel::Role::API;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'preferences',
);
my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    preferences => {
        data => {
            subscriber_id  =>  sub { return shift->get_id('subscribers',@_); },
        },
    },
});
#my $fake_data_processed = $fake_data->process('preferences');
#$test_machine->DATA_ITEM_STORE($fake_data->process('preferences'));
#$test_machine->form_data_item( );

#NGCP::Panel::Role::API::process_patch_description();
#my $entity = {'uri' => '/api/subscriberpreferences/'.$test_machine->DATA_ITEM->{subscriber_id}};
my $entity = {'uri' => '/api/subscriberpreferences/205'};

(undef, $entity->{content}) = $test_machine->check_item_get($entity->{uri});

NGCP::Panel::Role::API->apply_patch($c_mock, $entity->{content}, '
[
    { "op": "add","path":"/allowed_clis/3/boredpanda","value":["111","222","333"],"mode":"append"},
    { "op": "add","path":"/allow_out_foreign_domain","value":true},
    { "op": "add","path":"/concurrent_max","value":3}
]');
#NGCP::Panel::Role::API->apply_patch($c_mock, $entity->{content}, '
#[
#    { "op": "remove", "path":"/allowed_clis","value":["111","222","333"],"mode":"append"},
#    { "op": "remove","path":"/allow_out_foreign_domain","value":true},
#    { "op": "remove","path":"/concurrent_max","value":3}
#]');
done_testing;