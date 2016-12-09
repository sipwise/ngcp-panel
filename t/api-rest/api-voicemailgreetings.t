use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use JSON;
use Test::More;
use Data::Dumper;
use File::Basename;
use File::Slurp qw/read_file/;

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

my $greeting = $test_machine->check_create_correct( 1 )->[0];

my $req = $test_machine->get_request_get($greeting->{location});
$req->header('Accept' => 'audio/x-wav');
my ($res) = $test_machine->request_get(undef, $req);
$test_machine->http_code_msg(200, "check download ", $res);
is($res->filename, "voicemail_".$greeting->{content}->{dir}."_".$greeting->{content}->{subscriber_id}.".wav","Check downloaded file name.");
is(length($res->content), length(read_file($test_machine->DATA_ITEM_STORE->{greetingfile}, binmode => ':raw')),"Check length of the downloaded file");

$test_machine->check_get2put( { 
    'data_cb' => sub { 
        $_[0] = { 
            'json' => JSON::to_json($_[0]), 
            'greetingfile' =>  $test_machine->DATA_ITEM_STORE->{greetingfile} 
        }; 
    }
} );
$test_machine->check_bundle();
$test_machine->check_item_delete($greeting->{location});


$test_machine->clear_test_data_all();#fake data aren't registered in this test machine, so they will stay.


done_testing;

# vim: set tabstop=4 expandtab:
