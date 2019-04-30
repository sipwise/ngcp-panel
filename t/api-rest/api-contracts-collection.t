use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use DateTime;
use DateTime::Format::Strptime;

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
$fake_data_bp_prepaid->process('billingprofiles');
$test_machine_bp_prepaid->DATA_ITEM_STORE($fake_data_bp_prepaid->process('billingprofiles'));
my $bps_prepaid = $test_machine_bp_prepaid->check_create_correct( 3, sub { $_[0]->{prepaid} = 1; $_[0]->{name} .= time().Test::FakeData::seq; $_[0]->{handle} .= time().Test::FakeData::seq; } );
my $bps_no_prepaid = $test_machine_bp_prepaid->check_create_correct( 3, sub { $_[0]->{prepaid} = 0; $_[0]->{name} .= time().Test::FakeData::seq; $_[0]->{handle} .= time().Test::FakeData::seq; } );
my $bp_no_prepaid = pop @$bps_no_prepaid;
my $bp_prepaid = pop @$bps_prepaid;


my $dtf = DateTime::Format::Strptime->new(
    pattern => '%F %T',
); #DateTime::Format::Strptime->new( pattern => '%Y-%m-%d %H:%M:%S' );
my $now = DateTime->now(
    time_zone => DateTime::TimeZone->new(name => 'local')
);
my $data = clone $test_machine->DATA_ITEM;
delete $data->{billing_profile_id};
$data->{billing_profile_definition} = 'profiles';
$data->{billing_profiles} = [{'profile_id' => $bp_no_prepaid->{content}->{id}}, map { {
        'profile_id' => $_->{content}->{id},
        'start' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
        'stop' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
    } } @$bps_prepaid, @$bps_no_prepaid ];
($res,$content) = $test_machine->request_post( $data );
$test_machine->http_code_msg(422, "Check that we can not use prepaid billing plans for resellers/peers", $res, $content);
like($content->{message},qr!Peering/reseller contract can't be connected to the prepaid billing profile \d+\.!);

$data->{billing_profiles} = [map { {
        'profile_id' => $_->{content}->{id},
        'start' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
        'stop' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
    } } @$bps_prepaid, @$bps_no_prepaid ];
($res,$content) = $test_machine->request_put( $data, $contract_ok->{location} );
$test_machine->http_code_msg(422, "Check that we can not use prepaid billing plans in PUT for resellers/peers", $res, $content);
like($content->{message},qr!Peering/reseller contract can't be connected to the prepaid billing profile \d+\.!);

$data = clone $test_machine->DATA_ITEM;
$data->{billing_profile_id} = $bp_prepaid->{content}->{id};
($res,$content) = $test_machine->request_post( $data );
$test_machine->http_code_msg(422, "Check that we can not use prepaid billing plans in PATCH for resellers/peers", $res, $content);
like($content->{message},qr!Peering/reseller contract can't be connected to the prepaid billing profile \d+\.!);

($res,$content) = $test_machine->request_patch( [ { op => 'replace', path => '/billing_profile_id', value => $bp_prepaid->{content}->{id} } ] );
$test_machine->http_code_msg( 422, "Check that we can not use prepaid billing plans for resellers/peers", $res, $content);
like($content->{message},qr!Peering/reseller contract can't be connected to the prepaid billing profile \d+\.!);



#but check that we still create correctly contract with no prepaid billing profiles:
$data = clone $test_machine->DATA_ITEM;
delete $data->{billing_profile_id};
$data->{billing_profile_definition} = 'profiles';
$data->{billing_profiles} = [{'profile_id' => $bp_no_prepaid->{content}->{id}}, map { {
        'profile_id' => $_->{content}->{id},
        'start' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
        'stop' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
    } } @$bps_no_prepaid ];
($res,$content) = $test_machine->request_post( $data );
$test_machine->http_code_msg(201, "Check that we can create contracts if there aren't prepaid billing ptofiles", $res, $content);

$data->{billing_profiles} = [map { {
        'profile_id' => $_->{content}->{id},
        'start' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
        'stop' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
    } } @$bps_no_prepaid ];
($res,$content) = $test_machine->request_put( $data, $contract_ok->{location} );
$test_machine->http_code_msg(200,"Check that we can PUT contracts if there aren't prepaid billing ptofiles", $res, $content);

($res,$content) = $test_machine->request_patch( [ { op => 'replace', path => '/billing_profile_id', value => $bp_no_prepaid->{content}->{id} } ] );
$test_machine->http_code_msg(200,"Check that we can $data->{billing_profiles} = [{'profile_id' => $bp_no_prepaid->{content}->{id}}, map { {
        'profile_id' => $_->{content}->{id},
        'start' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
        'stop' => $dtf->format_datetime($now->add( days => Test::FakeData::seq)),
    } } @$bps_prepaid, @$bps_no_prepaid ]; contracts if there aren't prepaid billing ptofiles", $res, $content);

$data = clone $test_machine->DATA_ITEM;
$data->{billing_profile_id} = $bp_no_prepaid->{content}->{id};
($res,$content) = $test_machine->request_post( $data );
$test_machine->http_code_msg(201, "Check that we can create contracts if there aren't prepaid billing ptofiles", $res, $content);

#modify_timestamp - differs exactly because of the put.
#todo: create_timestamp - strange,  it is different to the value of the time zone
$test_machine->check_get2put({ignore_fields => [qw/modify_timestamp create_timestamp/]});
$test_machine->check_bundle();



$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();
$test_machine_bp_prepaid->clear_test_data_all();
undef $fake_data;
undef $test_machine;

done_testing;

# vim: set tabstop=4 expandtab:
