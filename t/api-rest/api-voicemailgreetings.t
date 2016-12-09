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
    'voicemailgreetings' => {
        'data' => {
            json => {
                dir           => 'unavail',
                subscriber_id => sub { return shift->get_id('subscribers',@_); },
            },
            greeting_file => [ dirname($0).'/resources/empty.txt' ],
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
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH)};


#$test_machine->form_data_item( sub {$_[0]->{json}->{dir} = $dir;} );
$test_machine->form_data_item();
# create 3 next new models from DATA_ITEM

$test_machine->check_create_correct( 1, sub{
} );

$test_machine->check_get2put( { 
    'data_cb' => sub { 
        $_[0] = { 
            'json' => JSON::to_json($_[0]), 
            'greeting_file' =>  $test_machine->DATA_ITEM_STORE->{greeting_file} 
        }; 
    }
} );

$test_machine->check_bundle();

done_testing;

# vim: set tabstop=4 expandtab:
