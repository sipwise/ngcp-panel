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
    name => 'lnpnumbers',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'lnpnumbers' => {
        data => {
            json => {
                carrier_id      => sub { return shift->get_id('lnpcarriers', @_); },
                number          => "112",
                routing_number  => "222",
                start           => "2016-10-03 00:00:00",
                start           => "2016-10-03 23:59:59",
            },
            file => [ (tempfile())[1] ],
        },
    },
});
my $data = $fake_data->process('lnpnumbers');
$test_machine->DATA_ITEM_STORE($data);

{#test "usual" interface

    $test_machine->DATA_ITEM($data->{json});
    $test_machine->check_create_correct( 3, sub{ $_[0]->{number} .= $_[1]->{i}; } );
    $test_machine->check_get2put();
    $test_machine->check_bundle();
    #we need to delete existing, if we want to check downloaded content later
    $test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.
}
{
#test "upload csv" interface variant
    $test_machine->DATA_ITEM($data);
    my $csv_data = <<EOS_CSV;
aaa,111,222,2221,2016-10-02,2016-10-31,1,1
aaa,111,333,3331,2016-10-01,2016-10-31,1,1
EOS_CSV
    my $csv_upload_url = '/api/lnpnumbers/';
    my $csv_download_url = '/api/lnpnumbers/';
    $test_machine->resource_fill_file($test_machine->DATA_ITEM->{file}->[0], $csv_data);
    {
        my $content_type_old = $test_machine->content_type;
        $test_machine->content_type->{POST} = 'text/csv';
        my($res,$content) = $test_machine->request_post($csv_data, $csv_upload_url.'?purge_existing=true');#
        $test_machine->http_code_msg(201, "check file upload", $res, $content);
        $test_machine->content_type($content_type_old);
    }
    {
        my $req = $test_machine->get_request_get( $csv_download_url );
        $req->header('Accept' => 'text/csv');
        my($res,$content) = $test_machine->request($req);
        my $filename = "lnp_list.csv";
        $test_machine->http_code_msg(200, "check response code", $res, $content);
        is($res->filename, $filename, "check downloaded csv filename: $filename;");
        is($res->content, $csv_data, "check downloaded content;");
    }
    {
        #clear off uploaded mappings, as  they out of the Collection control
        my $content_type_old = $test_machine->content_type;
        $test_machine->content_type->{POST} = 'text/csv';
        my($res,$content) = $test_machine->request_post("nope", $csv_upload_url.'?purge_existing=true');
        $test_machine->http_code_msg(201, "check file upload", $res, $content);
        $test_machine->content_type($content_type_old);
    }
}
$test_machine->clear_test_data_all();
undef $test_machine;
undef $fake_data;
done_testing;

# vim: set tabstop=4 expandtab:
