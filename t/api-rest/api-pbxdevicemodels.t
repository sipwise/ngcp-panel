use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use JSON;
use Test::More;
use Data::Dumper;
use File::Basename;

#init test_machine
my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'pbxdevicemodels' => {
        'data' => {
            json => {
                model       => "api_test ATA111",
                #reseller_id=1 is very default, as is seen from the base initial script
                #reseller_id => "1",
                reseller_id => sub { return shift->get_id('resellers',@_); },
                vendor      =>"Cisco",
                #3.7relative tests
                type               => "phone",
                connectable_models => [],
                extensions_num     => "2",
                bootstrap_method   => "http",
                bootstrap_uri      => "",
                bootstrap_config_http_sync_method            => "GET",
                bootstrap_config_http_sync_params            => "[% server.uri %]/\$MA",
                bootstrap_config_http_sync_uri               => "http=>//[% client.ip %]/admin/resync",
                bootstrap_config_redirect_panasonic_password => "",
                bootstrap_config_redirect_panasonic_user     => "",
                bootstrap_config_redirect_polycom_password   => "",
                bootstrap_config_redirect_polycom_profile    => "",
                bootstrap_config_redirect_polycom_user       => "",
                bootstrap_config_redirect_yealink_password   => "",
                bootstrap_config_redirect_yealink_user       => "",
                bootstrap_config_redirect_snom_password      => "",
                bootstrap_config_redirect_snom_user          => "",
                #TODO:implement checking against this number in the controller and api
                #/3.7relative tests
                "linerange"=>[
                    {
                        "keys" => [
                            {y => "390", labelpos => "left", x => "510"},
                            {y => "350", labelpos => "left", x => "510"}
                        ],
                        can_private   => "1",
                        can_shared    => "0",
                        can_blf       => "0",
                        can_speeddial => "0",
                        can_forward   => "0",
                        can_transfer  => "0",
                        name          => "Phone Ports api_test",
                        #TODO: test duplicate creation #"id"=>1311,
                    },
                    {
                        "keys"=>[
                            {y => "390", labelpos => "left", x => "510"},
                            {y => "350", labelpos => "left", x => "510"}
                        ],
                        can_private   => "1",
                        can_shared    => "0",
                        #TODO: If I'm right - now we don't check field values against this, because test for pbxdevice xreation is OK
                        can_blf       => "0",
                        can_speeddial => "0",
                        can_forward   => "0",
                        can_transfer  => "0",
                        name          => "Extra Ports api_test",
                        #TODO: test duplicate creation #"id"=>1311,
                    }
                ]
            },
            #TODO: can check big files
            #front_image => [ dirname($0).'/resources/api_devicemodels_front_image.jpg' ],
            front_image => [ dirname($0).'/resources/empty.txt' ],
            front_thumbnail => [ dirname($0).'/resources/empty.txt' ],
        },
        'query' => [ ['model','json','model'] ],
        'no_delete_available' => 1,
        'data_callbacks' => {
            'get2put' => $fake_data->get2put_upload_callback('pbxdevicemodels'),
            #'get2put' => Test::FakeData::get2put_upload_callback(),
            'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{json}->{model}); },
        }
    },
});
my $test_machine = Test::Collection->new(
    name => 'pbxdevicemodels',
    embedded_resources => [qw/pbxdevicefirmwares/]
);
$test_machine->DATA_ITEM_STORE($fake_data->process('pbxdevicemodels'));
@{$test_machine->content_type}{qw/POST PUT/}    = (('multipart/form-data') x 2);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH)};


my $connactable_devices={};
my $time = time();
foreach my $type(qw/extension phone/){
    #last;#skip classic tests
    $test_machine->form_data_item( sub {$_[0]->{json}->{type} = $type;} );
    # create 3 & 3 new billing models from DATA_ITEM
    $test_machine->check_create_correct( 1, sub{ $_[0]->{json}->{model} .= $type."TEST_".$_[1]->{i}.'_'.$time; } );
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
    $test_machine->check_create_correct( 1, sub{
        $_[0]->{json}->{model} .= $type."TEST_".($_[1]->{i} + 3).'_'.$time;
        $_[0]->{json}->{connactable_devices} = $connactable_devices->{ get_connectable_type( $type) }->{ids};
    } );
    $test_machine->check_get2put( { 
        'data_cb' => $fake_data->{data}->{'pbxdevicemodels'}->{data_callbacks}->{get2put},
    } );

    $test_machine->check_bundle();

    # try to create model without reseller_id
    {
        my ($res, $err) = $test_machine->check_item_post(sub{delete $_[0]->{json}->{reseller_id};});
        is($res->code, 422, "create model without reseller_id");
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
    }
    # try to create model with empty reseller_id
    {
        my ($res, $err) = $test_machine->check_item_post(sub{$_[0]->{json}->{reseller_id} = undef;});
        is($res->code, 422, "create model with empty reseller_id");
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /field='reseller_id'/, "check error message in body");
    }
    # try to create model with invalid reseller_id
    {
        my ($res, $err) = $test_machine->check_item_post(sub{$_[0]->{json}->{reseller_id} = 99999;});
        is($res->code, 422, "create model with invalid reseller_id");
        is($err->{code}, "422", "check error code in body");
        ok($err->{message} =~ /Invalid reseller_id/, "check error message in body");
    }

    {
        my (undef, $item_first_get) = $test_machine->check_item_get;
        ok(exists $item_first_get->{reseller_id} , "check existence of the reseller_id");
        cmp_ok($item_first_get->{reseller_id}, '>', 0, "check validity of the reseller_id");
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
#`echo 'delete from autoprov_devices where model like "%api_test %" or model like "patched model%";'|mysql -u root provisioning`;
done_testing;

# vim: set tabstop=4 expandtab:
