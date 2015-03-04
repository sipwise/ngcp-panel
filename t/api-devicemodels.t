#use Sipwise::Base;
use strict;

use Moose;
use lib "/root/VMHost/ngcp-panel/t/lib/";
extends 'Test::Collection';
use Net::Domain qw(hostfqdn);
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Test::More;
use Data::Dumper;
use File::Basename;

#init test_machine
my $test_machine = Test::Collection->new( 
    name => 'pbxdevicemodels', 
    embedded => [qw/pbxdevicefirmwares/]
);
$test_machine->CONTENT_TYPE->{POST} = 'multipart/form-data';
$test_machine->CONTENT_TYPE->{PUT}  = 'multipart/form-data';
#for item creation test purposes
$test_machine->DATA_ITEM({
    json => {
        "model"=>"ATA11",
        #3.7relative tests
        "type"=>"phone",
        "bootstrap_method"=>"http",
        #"bootstrap_config_http_sync_uri"=>"http=>//[% client.ip %]/admin/resync",
        #"bootstrap_config_http_sync_params"=>"[% server.uri %]/$MA",
        #"bootstrap_config_http_sync_method"=>"GET",
        #/3.7relative tests
        "reseller_id"=>"1",
        "vendor"=>"Cisco",
        "linerange"=>[
            {
                "keys"=>[
                    {"y"=>"390","labelpos"=>"left","x"=>"510"},
                    {"y"=>"350","labelpos"=>"left","x"=>"510"}
                ],
                "can_private"=>"1",
                "can_shared"=>"0",
                "can_blf"=>"0",
                "name"=>"Phone Ports",
#test duplicate creation #"id"=>1311,
            }
        ]
    },
    #'front_image' => [ dirname($0).'/resources/api_devicemodels_front_image.jpg' ],
    'front_image' => [ dirname($0).'/resources/empty.txt' ],
});


#collection tests, specific and common
$test_machine->check_options_collection;

# create 6 new billing models
$test_machine->check_create_correct( 6, sub{ $_[0]->{json}->{model} .= "_".$_[1]->{i}; } );

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

# iterate over collection to check next/prev links and status
my $listed = $test_machine->check_list_collection();
$test_machine->check_created_listed($listed);

# test model item
$test_machine->check_options_item;
$test_machine->check_put_bundle;
$test_machine->check_get2put( sub { $_[0] = { json => JSON::to_json($_[0]), 'front_image' =>  $test_machine->DATA_ITEM->{front_image} }; } );

{
    my $item_first_get = $test_machine->check_item_get;
    ok(exists $item_first_get->{reseller_id} && $item_first_get->{reseller_id}->is_int, "check existence of reseller_id");
    foreach(qw/vendor model/){
        ok(exists $item_first_get->{$_}, "check existence of $_");
    }
    # check if we have the proper links
    # TODO: fees, reseller links
    #ok(exists $new_contract->{_links}->{'ngcp:resellers'}, "check put presence of ngcp:resellers relation");
}
{
    my $t = time;
    my($res,$mod_model) = $test_machine->request_patch( [ { op => 'replace', path => '/model', value => 'patched model '.$t } ] );
    is($mod_model->{name}, "patched name $t", "check patched replace op");
}
{
    my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/reseller_id', value => undef } ] );
    is($res->code, 422, "check patched undef reseller");
}
{
    my($res) = $test_machine->request_patch( [ { op => 'replace', path => '/reseller_id', value => 99999 } ] );
    is($res->code, 422, "check patched invalid reseller");
}
`echo 'delete from autoprov_devices where model like "%\_%";'|mysql provisioning`;
done_testing;

# vim: set tabstop=4 expandtab:
