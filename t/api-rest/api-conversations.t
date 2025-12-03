use strict;
use warnings;

use Test::More;
use Test::Collection;
use Test::FakeData;
use Data::Dumper;

my $test_machine = Test::Collection->new(
    name => 'conversations',
);

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    conversations => {
        data => {
            customer_id  =>  sub { return shift->get_id('customers',@_); },
            subscriber_id  =>  sub { return shift->get_id('subscribers',@_); },
        },
    },
});
$test_machine->DATA_ITEM_STORE($fake_data->process('conversations'));

my @TYPES = qw/call voicemail fax sms/;

foreach my $owner_param ( map {'?'.$_.'='.$test_machine->DATA_ITEM->{$_}}
    qw/customer_id subscriber_id/
) {
    foreach my $type_params ('', map {'&type='.$_} @TYPES) {
        foreach my $sort_params ('', map {'&order_by='.$_} qw/type timestamp/) {
            my $uri = '/api/conversations/'.$owner_param.$type_params.$sort_params;
            my ($res, $content, $req) = $test_machine->request_get($uri);
            $test_machine->http_code_msg(200, "check $uri", $res, $content);
        }
    }
}

done_testing;

# vim: set tabstop=4 expandtab:
