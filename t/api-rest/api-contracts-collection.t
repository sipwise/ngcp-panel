use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'contracts',
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    'contracts' => {
        'data' => {
            status             => 'active',
            contact_id         => sub { return shift->get_id('systemcontacts',@_); },
            billing_profile_id => sub { return shift->get_id('billingprofiles',@_); },
            max_subscribers    => undef,
            external_id        => 'api_test contract'.time(),
            type               => 'reseller',
        },
        'query' => ['external_id'],
        'no_delete_available' => 1,
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('contracts'));
$test_machine->form_data_item( );
# create new contract from DATA_ITEM
my $contract_ok = $test_machine->check_create_correct( 1, sub{ $_[0]->{external_id} .=  $_[1]->{i}; } )->[0];

my ($res,$req,$content);


#todo: failed test 'check create_timestamp not empty '
#ok(length($mod_contract->{create_timestamp}) > 8 , "check create_timestamp not empty ".$mod_contract->{create_timestamp});
#ok(length($mod_contract->{modify_timestamp}) > 8 , "check modify_timestamp not empty ".$mod_contract->{modify_timestamp});


my $test_machine_bp_prepaid = Test::Collection->new(
    name => 'billingprofiles',
    QUIET_DELETION => 1,
);
my $fake_data_bp_prepaid = Test::FakeData->new(
    keep_db_data => 1,
    test_machine => $test_machine_bp_prepaid,
);
$fake_data_bp_prepaid->load_collection_data('billingprofiles');
$fake_data_bp_prepaid->apply_data({
    'billingprofiles' => {
        'prepaid' => 1,
    },
});
$fake_data_bp_prepaid->process('billingprofiles');
$test_machine_bp_prepaid->DATA_ITEM_STORE($fake_data_bp_prepaid->process('billingprofiles'));
my $bps_prepaid = $test_machine_bp_prepaid->check_create_correct( 3 );
my $bps_no_prepaid = $test_machine_bp_prepaid->check_create_correct( 3 );


($res,$req,$content) = $test_machine->check_create_correct( 1, sub{ $_[0]->{external_id} .=  $_[1]->{i}; } )->[0]



#modify_timestamp - differs exactly because of the put.
#todo: create_timestamp - strange,  it is different to the value of the time zone
$test_machine->check_get2put({ignore_fields => [qw/modify_timestamp create_timestamp/]});
$test_machine->check_bundle();



$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();
undef $fake_data;
undef $test_machine;

done_testing;

# vim: set tabstop=4 expandtab:
