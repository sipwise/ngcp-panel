use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;
use Data::Dumper;


#init test_machine
my $test_machine = Test::Collection->new(
    name => 'vouchers',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'vouchers' => {
        data => {
            amount => 100,
            code => 'apitestcode',
            customer_id => undef,
            package_id => undef,
            reseller_id => sub { return shift->get_id('resellers', @_); },
            valid_until => '2037-01-01 12:00:00',
        },
        'query' => ['code','reseller_id'],
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('vouchers'));
$test_machine->form_data_item( );

# create 3 new vouchers from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{code} .= time().'_'.$_[1]->{i} ; } );
$test_machine->check_get2put();
$test_machine->check_bundle();

my $voucher = $test_machine->{DATA_ITEM};
print Dumper $voucher;
my $voucher_uri;

{
    #todo: move request processing results to separate package inside collection, to don't return these chains
    my($post,$get_post) = $test_machine->check_post2get();
    $voucher_uri = $post->{location};
    my($put,$get_put) = $test_machine->check_put2get( {}, {'uri' => $voucher_uri} );

    $voucher = $get_put->{content};

    my($res_patch,$patch_voucher) = $test_machine->request_patch(  [ { op => 'replace', path => '/code', value => $put->{content}->{code} } ], $voucher_uri );
    delete $put->{content}->{_links};
    delete $put->{content}->{id};
    delete $patch_voucher->{_links};
    delete $patch_voucher->{id};
    is_deeply($put->{content}, $patch_voucher, "check PATCHed voucher against POSTed voucher");

    my($res,$result_item,$req) = $test_machine->request_post($voucher);
    $test_machine->http_code_msg(422, "POST same voucher code again", $res, $result_item);
}
{
    my($res,$content) = $test_machine->request_patch(  [ { op => 'replace', path => '/valid_until', value => '2099-01-01 00:00:00' } ] );
    $test_machine->http_code_msg(422, "check patched invalid billing_zone_id",$res,$content);
}

$test_machine->clear_test_data_all();

{
    my $uri = $test_machine->get_uri($voucher->{id});
    my($req,$res,$content) = $test_machine->request_delete($uri);
    $test_machine->http_code_msg(204, "check delete of voucher", $res, $content);
    ($res, $content, $req) = $test_machine->request_get($uri);
    is($res->code, 404, "check if deleted voucher is really gone");
}
done_testing;

# vim: set tabstop=4 expandtab:
