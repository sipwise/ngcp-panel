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

#init test_machine
my $test_machine = Test::Collection->new( 
    name => 'pbxdevicemodels', 
    embedded => [qw/pbxdevicefirmwares/]
);
@{$test_machine->content_type}{qw/POST PUT/}    = (('multipart/form-data') x 2);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH)};
#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE({
    json => {
        "model"=>"ATA111",
        #should be some fake reseller - create reseller/customer/subscriber tests?
        #"reseller_id"=>"1",
        "vendor"=>"Cisco",
        #3.7relative tests
        "bootstrap_method"=>"http",
        "bootstrap_uri"=>"",
        "bootstrap_config_http_sync_method"=>"GET",
        "bootstrap_config_http_sync_params"=>"[% server.uri %]/\$MA",
        "bootstrap_config_http_sync_uri"=>"http=>//[% client.ip %]/admin/resync",
        "bootstrap_config_redirect_panasonic_password"=>"",
        "bootstrap_config_redirect_panasonic_user"=>"",
        "bootstrap_config_redirect_polycom_password"=>"",
        "bootstrap_config_redirect_polycom_profile"=>"",
        "bootstrap_config_redirect_polycom_user"=>"",
        "bootstrap_config_redirect_yealink_password"=>"",
        "bootstrap_config_redirect_yealink_user"=>"",
        "type"=>"phone",
        "connectable_models"=>[702,703,704],
        "extensions_num"=>"2",
        #/3.7relative tests
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
    #can check big files
    #'front_image' => [ dirname($0).'/resources/api_devicemodels_front_image.jpg' ],
    'front_image' => [ dirname($0).'/resources/empty.txt' ],
});



##$test_machine->form_data_item( sub {$_[0]->{json}->{type} = "extension";} );
##$test_machine->check_create_correct( 1, sub{ $_[0]->{json}->{model} .= "Extension 2".$_[1]->{i}; } );
#$test_machine->check_get2put( sub { 
#    $_[0]->{connectable_models} = [670],
#    $_[0] = { 
#        json => JSON::to_json($_[0]), 
#        'front_image' =>  $test_machine->DATA_ITEM_STORE->{front_image} 
#    }; },
#    $test_machine->get_uri_collection.'449'
#);
#
##test check_patch_prefer_wrong is broken
##$test_machine->name('billingprofiles');
##$test_machine->check_patch_prefer_wrong;


foreach my $type(qw/phone extension/){
    #last;#skip classic tests
    $test_machine->form_data_item( sub {$_[0]->{json}->{type} = $type;} );
    # create 6 new billing models from DATA_ITEM
    $test_machine->check_create_correct( 6, sub{ $_[0]->{json}->{model} .= $type."TEST_".$_[1]->{i}; } );
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
        # TODO: fees, reseller links
        #ok(exists $new_contract->{_links}->{'ngcp:resellers'}, "check put presence of ngcp:resellers relation");
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
`echo 'delete from autoprov_devices where model like "%TEST\\_%" or model like "patched model%";'|mysql provisioning`;
done_testing;

# vim: set tabstop=4 expandtab:
