#use Sipwise::Base;
use strict;

#use Moose;
use Sipwise::Base;
use NGCP::Panel::Utils::Test::Collection;
use NGCP::Panel::Utils::Test::FakeData;
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Test::More;
use Data::Dumper;


#init test_machine
my $fake_data = NGCP::Panel::Utils::Test::FakeData->new;
my $test_machine = NGCP::Panel::Utils::Test::Collection->new( 
    name => 'pbxdevicemodels', 
    embedded => [qw/pbxdevicefirmwares/]
);
@{$test_machine->content_type}{qw/POST PUT/}    = (('multipart/form-data') x 2);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH)};
$test_machine->KEEP_CREATED( 1 );
$test_machine->DATA_ITEM_STORE($fake_data->process('pbxdevicemodels'));


my $connactable_devices={};

foreach my $type(qw/extension phone/){
    #last;#skip classic tests
    $test_machine->form_data_item( sub {$_[0]->{json}->{type} = $type;} );
    # create 3 & 3 new billing models from DATA_ITEM
    $test_machine->check_create_correct( 3, sub{ $_[0]->{json}->{model} .= $type."TEST_".$_[1]->{i}; } );
    #print Dumper $test_machine->DATA_CREATED->{ALL};
    $connactable_devices->{$type}->{data} = [ values %{$test_machine->DATA_CREATED->{ALL}}];
    $connactable_devices->{$type}->{ids} = [ map {$test_machine->get_id_from_created($_)} @{$connactable_devices->{$type}->{data}}];
}
sub get_connectable_type{
    my $type = shift;
    return ('extension' eq $type) ? 'phone' : 'extension';
}
foreach my $type(qw/extension phone/){
    #last;#skip classic tests
    $test_machine->form_data_item( sub {$_[0]->{json}->{type} = $type;} );
    # create 3 next new models from DATA_ITEM
    $test_machine->check_create_correct( 3, sub{ 
        $_[0]->{json}->{model} .= $type."TEST_".($_[1]->{i} + 3); 
        $_[0]->{json}->{connactable_devices} = $connactable_devices->{ get_connectable_type( $type) }->{ids};
    } );
    $test_machine->check_get2put( sub { $_[0] = { json => JSON::to_json($_[0]), 'front_image' =>  $test_machine->DATA_ITEM_STORE->{front_image} }; } );
    
    $test_machine->check_bundle();

    # try to create model without reseller_id
    {
        my ($res, $err) = $test_machine->request_post(sub{delete $_[0]->{json}->{reseller_id};});
        is($res->code, 422, "create model without reseller_id");
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
    }
    # try to create model with empty reseller_id
    {
        my ($res, $err) = $test_machine->request_post(sub{$_[0]->{json}->{reseller_id} = undef;});
        is($res->code, 422, "create model with empty reseller_id");
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
    }
    # try to create model with invalid reseller_id
    {
        my ($res, $err) = $test_machine->request_post(sub{$_[0]->{json}->{reseller_id} = 99999;});
        is($res->code, 422, "create model with invalid reseller_id");
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /Invalid reseller_id/, "check error message in body");
    } 

    {
        my (undef, $item_first_get) = $test_machine->check_item_get;
        ok(exists $item_first_get->{reseller_id} && $item_first_get->{reseller_id}->is_int, "check existence of reseller_id");
        foreach(qw/vendor model/){
            ok(exists $item_first_get->{$_}, "check existence of $_");
        }
        # check if we have the proper links
    }
    {
        my $t = time;
        my($res,$mod_model) = $test_machine->check_patch_correct( [ { op => 'replace', path => '/model', value => 'patched model '.$t } ] );
        is($mod_model->{model}, "patched model $t", "check patched replace op");
    }
    {
        my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/reseller_id', value => undef } ] );
        is($res->code, 422, "check patched undef reseller");
    }
    {
        my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/reseller_id', value => 99999 } ] );
        is($res->code, 422, "check patched invalid reseller");
    }
}
#pbxdevicemodels doesn't have DELETE method
#comment it if you want to inspect created test data manually. After this please don't forget to remove test data
`echo 'delete from autoprov_devices where model like "%TEST\\_%" or model like "patched model%";'|mysql provisioning`;
done_testing;

# vim: set tabstop=4 expandtab:
