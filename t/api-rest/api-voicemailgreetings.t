use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use JSON;
use Test::More;
use Data::Dumper;
use File::Basename;
use File::Slurp qw/read_file write_file/;
use File::Temp;
use NGCP::Panel::Utils::Generic qw(:all);

#init test_machine
my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'voicemailgreetings' => {
        'data' => {
            json => {
                dir           => 'unavail',
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
            },
            greetingfile => [ dirname($0).'/resources/test.wav' ],
        },
        'query' => [ ['dir', 'json', 'dir'] ],
        'create_special'=> $fake_data->create_special_upload(),
    },
});
my $test_machine = Test::Collection->new(
    name => 'voicemailgreetings',
);
$test_machine->DATA_ITEM_STORE($fake_data->process('voicemailgreetings'));
@{$test_machine->content_type}{qw/POST PUT/}    = (('multipart/form-data') x 2);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT DELETE)};


#$test_machine->form_data_item( sub {$_[0]->{json}->{dir} = $dir;} );
$test_machine->form_data_item();

my ($res,$content,$req);
my $greeting = $test_machine->check_create_correct( 1 )->[0];
print Dumper $greeting->{content};
ok(is_int($greeting->{content}->{id}), "Check id presence after creation.");
ok(is_int($greeting->{content}->{subscriber_id}), "Check subscriber_id presence after creation.");
is($greeting->{content}->{subscriber_id}, $test_machine->DATA_ITEM->{json}->{subscriber_id}, "Check subscriber_id after creation.");
ok($greeting->{content}->{dir} =~/^(?:unavail|busy)$/, "Check dir after creation.");
is($greeting->{content}->{dir}, $test_machine->DATA_ITEM->{json}->{dir}, "Check dir after creation #2.");

$res = $test_machine->request_get($greeting->{location}, undef, {
    'Accept' => 'audio/x-wav',
});
$test_machine->http_code_msg(200, "check download voicemail greeting", $res);

my $expected_downloaded_name = "voicemail_".$greeting->{content}->{dir}."_".$greeting->{content}->{subscriber_id}.".wav";
is($res->filename, $expected_downloaded_name ,"Check downloaded file name: $expected_downloaded_name .");
ok(length($res->content)>0,"Check length of the downloaded file > 0 :".length($res->content));

my $uploaded_path = $test_machine->DATA_ITEM_STORE->{greetingfile}->[0];

my $dir = File::Temp->newdir(undef, CLEANUP => 0);
my $tempdir = $dir->dirname;
my $downloaded_path = $tempdir.'/'.$expected_downloaded_name;
write_file( $downloaded_path , {binmode => ':raw'}, $res->content);
my $soxi_output = `soxi -e $downloaded_path`;
$soxi_output=~s/\n//g;

if(ok($soxi_output =~/GSM/, "Check that we converted wav to GSM encoding:".$soxi_output)){
    my $soxi_output_original = `soxi -e $uploaded_path`;
    $soxi_output_original=~s/\n//g;
    if(ok($soxi_output_original ne $soxi_output, "Check that we used non GSM encoded wav from the start")){
        diag("Time to test uploading of the wav file with GSM encoding");
        $test_machine->DATA_ITEM->{json}->{dir} = 'busy';
        ($res,$content,$req) = $test_machine->request_put( [ 
            'json' => JSON::to_json($test_machine->DATA_ITEM->{json}),
            greetingfile => [ $downloaded_path ],
        ] );

        ok(is_int($content->{id}),"Check id presence after editing.");
        ok(is_int($content->{subscriber_id}),"Check subscriber_id presence after editing.");
        is($content->{dir}, 'busy', "Check dir after editing.");
        is($content->{subscriber_id}, $content->{content}->{subscriber_id}, "Check subscriber_id after editing.");

        $uploaded_path = $downloaded_path;
        $test_machine->http_code_msg(200, "check update voicemail greeting with put. We used GSM file $downloaded_path.", $res);
        my $uploaded_content = read_file($downloaded_path, binmode => ':raw');
        my $res_download = $test_machine->request_get($greeting->{location}, undef, {
            'Accept' => 'audio/x-wav',
        });
        $test_machine->http_code_msg(200, "check download voicemail greeting after put", $res);
        is(length($res_download->content), length($uploaded_content),"Check length of the downloaded file: ".length($uploaded_content)."<=>".length($res_download->content));
    }
}
{
    diag("Check empty file:");
    #btw - other vriant of tha put data - closer to stored. will be changed by Collection::encode_content
    my ($res_put_empty,$content_put_empty) = $test_machine->request_put( {
        %{$test_machine->DATA_ITEM_STORE},
        greetingfile => [ dirname($0).'/resources/empty.wav' ],
    } );
    $test_machine->http_code_msg(422, "check response code on put empty file", $res_put_empty, $content_put_empty);
    diag("Check dirty file:");
    #btw - other vriant of tha put data - closer to stored. will be changed by Collection::encode_content
    my ($res_put_empty,$content_put_empty) = $test_machine->request_put( {
        %{$test_machine->DATA_ITEM_STORE},
        greetingfile => [ dirname($0).'/resources/empty.wav' ],
    } );
    $test_machine->http_code_msg(422, "check response code on put empty file", $res_put_empty, $content_put_empty);
}
$test_machine->check_bundle();
$test_machine->check_item_delete($greeting->{location});


$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.


done_testing;

# vim: set tabstop=4 expandtab:
