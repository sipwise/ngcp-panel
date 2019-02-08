use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use Clone qw/clone/;
use feature 'state';
#use NGCP::Panel::Utils::Subscriber;
#use Data::Compare qw//;

my $test_machine = Test::Collection->new(
    name => 'subscribers',
    QUIET_DELETION => 1,
);

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};
my $fake_data = Test::FakeData->new(
    keep_db_data => 1,
    test_machine => $test_machine,
);
$fake_data->load_collection_data('subscribers');
my $fake_data_processed = $fake_data->process('subscribers');

my $pilot = $test_machine->get_item_hal('subscribers','/api/subscribers/?customer_id='.$fake_data_processed->{customer_id}.'&'.'is_pbx_pilot=1');
if((exists $pilot->{total_count} && $pilot->{total_count}) || (exists $pilot->{content}->{total_count} && $pilot->{content}->{total_count} > 0) ){
    $fake_data_processed->{is_pbx_pilot} = 0;
    #remove pilot aliases to don't intersect with them. On subscriber termination admin adopt numbers, see ticket#4967
    $test_machine->request_patch(  [ { op => 'replace', path => '/alias_numbers', value => [] } ], $pilot->{location} );
}else{
    undef $pilot;
}
$test_machine->DATA_ITEM_STORE($fake_data_processed);
$test_machine->form_data_item();

my $remote_config = $test_machine->init_catalyst_config;
#modify time changes on every data change, and primary_number_id on every primary number change
my $put2get_check_params = { ignore_fields => $fake_data->data->{subscribers}->{update_change_fields} };


{
    my $member_to_terminate;
    my $member_to_get_number;
    my $pilot_local;
    my $alias_numbers = [
                { ac => '115', cc=> 15, sn => '50975' },
                { ac => '116', cc=> 16, sn => '50975' },
                { ac => '117', cc=> 17, sn => '50975' },
                { ac => '118', cc=> 18, sn => '50975' },
            ];
    if(!$pilot) {
        diag("50975: create pilot");
        $pilot = $test_machine->check_create_correct( 1, sub{
            my $num = $_[1]->{i}.Test::FakeData::seq;
            $_[0]->{username} .= time().'_50975_'.$num ;
            $_[0]->{webusername} .= time().'_'.$num;
            $_[0]->{pbx_extension} .= '50975'.$num;
            $_[0]->{primary_number}->{ac} .= $num;
            $_[0]->{is_pbx_group} = 0;
            $_[0]->{is_pbx_pilot} = 1;
            $_[0]->{alias_numbers} = $alias_numbers;
        } )->[0];
        $pilot_local = $pilot;
    } else {
        $pilot_local = $pilot;
        
        $test_machine->request_patch(  [ { op => 'replace', path => '/alias_numbers', value => $alias_numbers } ], $pilot_local->{location} );
    }
    diag("50975: attempt to remove alias_number by value without hashpartialfit");
    $test_machine->request_patch(  [ { 
        op => 'remove', 
        path => '/alias_numbers', 
        value => { ac => '115', cc=> '15', sn => '50975' },} ], $pilot_local->{location} );
    my ($aliases) = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$pilot_local->{content}->{id}, 1)->{collection};
    ok(((scalar @$aliases) == 4),"50975: aliases of ".$pilot_local->{content}->{id}." no one is removed without mode hashpartialfit:".(scalar @$aliases ));
    #print Dumper $aliases;
    diag("50975: attempt to remove alias_number by value with hashpartialfit");
    $test_machine->request_patch(  [ { 
        op => 'remove', 
        path => '/alias_numbers', 
        value => { ac => '115', cc=> '15', sn => '50975' },
        mode => 'hashpartialfit',
    } ], $pilot_local->{location} );
    $aliases = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$pilot_local->{content}->{id}, 1)->{collection};
    ok(((scalar @$aliases) == 3),"50975: aliases of ".$pilot_local->{content}->{id}." one is removed with mode hashpartialfit:".(scalar @$aliases ));
    diag("50975: attempt to remove wrong value");
    $test_machine->request_patch(  [ { 
        op => 'remove', 
        path => '/alias_numbers', 
        value => { ac => '1151', cc=> '15', sn => '50975' },} ], $pilot_local->{location} );
    $aliases = $test_machine->get_collection_hal('numbers', '/api/numbers/?type=alias&subscriber_id='.$pilot_local->{content}->{id}, 1)->{collection};
    ok(((scalar @$aliases) == 3),"50975: aliases of ".$pilot_local->{content}->{id}." no one is removed:".(scalar @$aliases ));
}

$test_machine->init_ssl_cert();
$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
$fake_data->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;



sub number_as_string{
    my ($number_row, %params) = @_;
    return 'HASH' eq ref $number_row
        ? $number_row->{cc} . ($number_row->{ac} // '') . $number_row->{sn}
        : $number_row->cc . ($number_row->ac // '') . $number_row->sn;
}

# vim: set tabstop=4 expandtab:
