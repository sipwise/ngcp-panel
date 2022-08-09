use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;
use File::Temp qw/tempfile/;
use Clone qw/clone/;
#init test_machine

my $test_machine = Test::Collection->new(
    name => 'emergencymappings',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'emergencymappings' => {
        data => {
            json => {
                emergency_container_id => sub { return shift->get_id('emergencymappingcontainers', @_); },
                code   => "112",
                prefix  => "000",
                suffix  => "321",
            },
            file => [ (tempfile())[1] ],
        },
        'query' => [['code','json','code'],['emergency_container_id','json','emergency_container_id']],
    },
});
my $data = $fake_data->process('emergencymappings');
$test_machine->DATA_ITEM_STORE($data);

{#test "usual" interface

    $test_machine->DATA_ITEM($data->{json});
    # create 3 new emergency mappings from DATA_ITEM
    $test_machine->check_create_correct( 3, sub{ $_[0]->{code} .= $_[1]->{i}; } );
    $test_machine->check_get2put();
    $test_machine->check_bundle();
    #we need to delete existing, if we want to check downloaded content later
    $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
}
{
#test "upload csv" interface variant
    $test_machine->DATA_ITEM($data);
    {
        my $empty_container_data = clone $test_machine->DATA_ITEM;
        $empty_container_data = delete $empty_container_data->{json};
        delete $empty_container_data->{emergency_container_id};
        my($res,$content) = $test_machine->request_post($empty_container_data);
        $test_machine->http_code_msg(422, "Emergency Mapping Container field is required", $res, $content);
    }

    my $container =  $test_machine->get_item_hal('emergencymappingcontainers');
    my $csv_data = "$container->{content}->{name},217,1122\n$container->{content}->{name},413,5123\n";
    my $csv_upload_url = '/api/emergencymappings/?reseller_id='.$container->{content}->{reseller_id};
    my $csv_download_url = '/api/emergencymappings/?reseller_id='.$container->{content}->{reseller_id};
    $test_machine->resource_fill_file($test_machine->DATA_ITEM->{file}->[0], $csv_data);
    {
        my $content_type_old = $test_machine->content_type;
        $test_machine->content_type->{POST} = 'text/csv';
        #my($res,$content) = $test_machine->request_post($test_machine->DATA_ITEM, $csv_upload_url);#.'&purge_existing=true'
        my($res,$content) = $test_machine->request_post($csv_data, $csv_upload_url.'&purge_existing=true');#
        $test_machine->http_code_msg(201, "check file upload", $res, $content);
        $test_machine->content_type($content_type_old);
    }
    {
        my $req = $test_machine->get_request_get( $csv_download_url );
        $req->header('Accept' => 'text/csv');
        my($res,$content) = $test_machine->request($req);
        my $filename = "emergency_mapping_list_reseller_".$container->{content}->{reseller_id}.".csv";
        $test_machine->http_code_msg(200, "check response code", $res, $content);
        is($res->filename, $filename, "check downloaded csv filename: $filename;");
        is($res->content, $csv_data, "check downloaded content;");
    }
    {
        my $req = $test_machine->get_request_get( '/api/emergencymappings' );
        $req->header('Accept' => 'text/csv');
        my($res,$content) = $test_machine->request($req);
        $test_machine->http_code_msg(400, "reseller_id parameter is necessary to download csv data", $res, $content);
    }
    {
        #clear off uploaded mappings, as  they out of the Collection control
        my $content_type_old = $test_machine->content_type;
        $test_machine->content_type->{POST} = 'text/csv';
        my($res,$content) = $test_machine->request_post("nope", $csv_upload_url);
        $test_machine->http_code_msg(201, "check file upload", $res, $content);
        $test_machine->content_type($content_type_old);
    }
}
$test_machine->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;

# vim: set tabstop=4 expandtab:
