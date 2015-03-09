#use Sipwise::Base;
use strict;

#use Moose;
use Sipwise::Base;
use lib "/root/VMHost/ngcp-panel/t/lib/";
extends 'Test::Collection';
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Test::More;
use Data::Dumper;
use File::Basename;
use bignum qw/hex/;

#init test_machine
my $test_machine = Test::Collection->new( 
    name => 'pbxdevices', 
    embedded => [qw/pbxdeviceprofiles customers/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};
#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE({
    'profile_id' => '115',
    'customer_id' => '968',
    'identifier' => 'aaaabbbbcccc',
    'station_name' => 'abc',
    'lines'=>[{
        'linerange' => 'Phone Ports',
        'type' => 'private',
        'key_num' => '0',
        'subscriber_id' => '1198',
        },{
        'linerange' => 'Phone Ports',
        'type' => 'private',
        'key_num' => '1',
        'subscriber_id' => '1198',
    }],
    #'extension.0.extension_id' => '670',
});


$test_machine->form_data_item( );
# create 6 new billing models from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{identifier} = sprintf('%x', (hex('0x'.$_[0]->{identifier}) + $_[1]->{i}) ); } );
$test_machine->check_get2put(  );
$test_machine->check_bundle();
$test_machine->check_delete_created();

## try to create model without reseller_id
#{
#    my ($res, $err) = $test_machine->request_post(sub{delete $_[0]->{json}->{reseller_id};});
#    is($res->code, 422, "create model without reseller_id");
#    is($err->{code}, "422", "check error code in body");
#    ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
#}
## try to create model with empty reseller_id
#{
#    my ($res, $err) = $test_machine->request_post(sub{$_[0]->{json}->{reseller_id} = undef;});
#    is($res->code, 422, "create model with empty reseller_id");
#    is($err->{code}, "422", "check error code in body");
#    ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
#}
## try to create model with invalid reseller_id
#{
#    my ($res, $err) = $test_machine->request_post(sub{$_[0]->{json}->{reseller_id} = 99999;});
#    is($res->code, 422, "create model with invalid reseller_id");
#    is($err->{code}, "422", "check error code in body");
#    ok($err->{message} =~ /Invalid reseller_id/, "check error message in body");
#} 
#
#{
#    my (undef, $item_first_get) = $test_machine->check_item_get;
#    ok(exists $item_first_get->{reseller_id} && $item_first_get->{reseller_id}->is_int, "check existence of reseller_id");
#    foreach(qw/vendor model/){
#        ok(exists $item_first_get->{$_}, "check existence of $_");
#    }
#    # check if we have the proper links
#    # TODO: fees, reseller links
#    #ok(exists $new_contract->{_links}->{'ngcp:resellers'}, "check put presence of ngcp:resellers relation");
#}
#{
#    my $t = time;
#    my($res,$mod_model) = $test_machine->check_patch_correct( [ { op => 'replace', path => '/model', value => 'patched model '.$t } ] );
#    is($mod_model->{model}, "patched model $t", "check patched replace op");
#}
#{
#    my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/reseller_id', value => undef } ] );
#    is($res->code, 422, "check patched undef reseller");
#}
#{
#    my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/reseller_id', value => 99999 } ] );
#    is($res->code, 422, "check patched invalid reseller");
#}

#`echo 'delete from autoprov_devices where model like "%TEST\\_%" or model like "patched model%";'|mysql provisioning`;
done_testing;

# vim: set tabstop=4 expandtab:
