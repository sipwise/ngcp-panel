use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'numbers',
    embedded_resources => [qw/subscribers/]
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH)};

my $fake_data =  Test::FakeData->new;
$fake_data->set_data_from_script({
    numbers => {
        data => {
            reseller_id   => sub { return shift->get_id('resellers',@_); },
            subscriber_id => sub { return shift->get_id('subscribers',@_); },
            e164 => {
                cc => '43',
                ac => '222',
                sn => '0000',
            }
        },
        query => ['reseller_id','subscriber_id'],
    },
});

#for item creation test purposes /post request data/
$test_machine->DATA_ITEM_STORE($fake_data->process('numbers'));

$test_machine->form_data_item( );
{
    my $data = $test_machine->DATA_ITEM;
    $data->{e164}->{sn} .= "1";
    my ($res,$result_item,$req) = $test_machine->request_post($data);
    $test_machine->http_code_msg(404, "POST number rejection", $res, $result_item);
}
$test_machine->check_get2put();
$test_machine->check_bundle();
$test_machine->clear_test_data_all();

undef $test_machine;
undef $fake_data;
done_testing;
# vim: set tabstop=4 expandtab:
