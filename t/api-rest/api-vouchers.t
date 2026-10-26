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

# csv upload
{
    my $reseller_id = $test_machine->DATA_ITEM->{reseller_id};
    my $t = time;

    #another reseller, whose vouchers are purged by an admin but not by a reseller
    my ($res, $content) = $test_machine->request_get('/api/resellers/?page=1&rows=10');
    my ($other_reseller) = grep { defined $_ && $_->{id} != $reseller_id }
        @{ $test_machine->get_embedded_forcearray($content, 'resellers') };
    my $other_reseller_id = $other_reseller->{id};
    ok($other_reseller_id, "found another reseller for the csv tests");

    #the vouchers of a reseller, by code
    my $vouchers_of = sub {
        my ($id) = @_;
        my (undef, $list) = $test_machine->request_get("/api/vouchers/?page=1&rows=100&reseller_id=$id");
        #an empty collection is returned as [undef]
        return { map { $_->{code} => $_ }
            grep { defined $_ } @{ $test_machine->get_embedded_forcearray($list) } };
    };

    $test_machine->content_type->{POST} = 'text/csv';

    ($res, $content) = $test_machine->request_post(
        "$other_reseller_id,csvother_$t,100,2037-01-01,\n", '/api/vouchers/');
    $test_machine->http_code_msg(201, "check csv upload for another reseller", $res, $content);
    ok(exists $vouchers_of->($other_reseller_id)->{"csvother_$t"}, "check the voucher of the other reseller is uploaded");

    ($res, $content) = $test_machine->request_post(
        "$reseller_id,csv1_$t,100,2037-01-01,\n".
        "$reseller_id,csv2_$t,200,2037-01-01 12:00:00,\n",
        '/api/vouchers/?purge_existing=true');
    $test_machine->http_code_msg(201, "check csv upload with purge_existing", $res, $content);
    ok(!exists $vouchers_of->($other_reseller_id)->{"csvother_$t"},
        "check the admin purge deleted the voucher of the other reseller");
    my $vouchers = $vouchers_of->($reseller_id);
    is_deeply([sort keys %{ $vouchers }], ["csv1_$t", "csv2_$t"], "check the uploaded vouchers");
    is($vouchers->{"csv1_$t"}->{amount}, 100, "check the amount of the first uploaded voucher");
    is($vouchers->{"csv1_$t"}->{valid_until}, '2037-01-01 23:59:59', "check a valid_until date lasts the whole day");
    is($vouchers->{"csv2_$t"}->{amount}, 200, "check the amount of the second uploaded voucher");
    is($vouchers->{"csv2_$t"}->{valid_until}, '2037-01-01 12:00:00', "check a valid_until date and time is kept");

    #a line with less than two fields is skipped, as in the web interface
    ($res, $content) = $test_machine->request_post(
        "$reseller_id\n$reseller_id,csv3_$t,300,2037-01-01,\n", '/api/vouchers/');
    $test_machine->http_code_msg(201, "check csv upload with a skipped line", $res, $content);
    my @expected = ("csv1_$t", "csv2_$t", "csv3_$t");
    is_deeply([sort keys %{ $vouchers_of->($reseller_id) }], \@expected, "check the line after the skipped one is uploaded");

    #the rejected uploads have to import nothing, and to purge nothing
    my $err;
    ($res, $err) = $test_machine->request_post(
        "$reseller_id,dup_$t,100,2037-01-01,\n$reseller_id,dup_$t,100,2037-01-01,\n",
        '/api/vouchers/?purge_existing=true');
    $test_machine->http_code_msg(422, "check csv upload with a duplicated code", $res, $err);
    like($err->{message}, qr/duplicated or already exists/, "check the duplicated code is reported");
    is_deeply([sort keys %{ $vouchers_of->($reseller_id) }], \@expected, "check the purge of the rejected upload is rolled back");

    ($res, $err) = $test_machine->request_post(
        "$reseller_id,csv1_$t,100,2037-01-01,\n", '/api/vouchers/');
    $test_machine->http_code_msg(422, "check csv upload with an existing code", $res, $err);
    like($err->{message}, qr/duplicated or already exists/, "check the existing code is reported");

    ($res, $err) = $test_machine->request_post(
        "$reseller_id,csv4_$t,100,2037-01-01,\n".
        "$reseller_id,csv\"5_$t,100,2037-01-01,\n".
        "$reseller_id,csv6_$t,100,2037-01-01,\n", '/api/vouchers/');
    $test_machine->http_code_msg(422, "check csv upload with a stray quote", $res, $err);
    like($err->{message}, qr/line 2 could not be parsed/, "check the line with a stray quote is reported");

    #an unterminated quoted field runs up to the end of the file, it used to
    #drop the rest of the file silently
    ($res, $err) = $test_machine->request_post(
        "$reseller_id,csv4_$t,100,2037-01-01,\n".
        "$reseller_id,\"csv5_$t,100,2037-01-01,\n".
        "$reseller_id,csv6_$t,100,2037-01-01,\n", '/api/vouchers/');
    $test_machine->http_code_msg(422, "check csv upload with an unterminated quote", $res, $err);
    like($err->{message}, qr/line 2 could not be parsed/, "check the line with an unterminated quote is reported");

    ($res, $err) = $test_machine->request_post(
        "$reseller_id,csv7_$t,100,2037-02-30,\n", '/api/vouchers/');
    $test_machine->http_code_msg(422, "check csv upload with an invalid valid_until", $res, $err);
    like($err->{message}, qr/line 1 has an invalid valid_until '2037-02-30'/, "check the invalid valid_until is reported");

    ($res, $err) = $test_machine->request_post(
        "$reseller_id,csv8_$t,100,2037-01-01,999999999\n", '/api/vouchers/');
    $test_machine->http_code_msg(422, "check csv upload with an unknown customer_id", $res, $err);
    like($err->{message}, qr/unknown reseller_id, customer_id or package_id/, "check the unknown customer_id is reported");

    is_deeply([sort keys %{ $vouchers_of->($reseller_id) }], \@expected, "check the rejected uploads changed nothing");

    #a reseller only purges its own vouchers
    ($res, $content) = $test_machine->request_post(
        "$other_reseller_id,resother_$t,100,2037-01-01,\n", '/api/vouchers/');
    $test_machine->http_code_msg(201, "check csv upload for another reseller", $res, $content);

    $test_machine->content_type->{POST} = 'application/json';
    my $reseller_admin = {
        reseller_id  => $reseller_id,
        login        => "apivouchers$t",
        password     => 'Vt9#kq2!Lm7$Rx4p',
        role         => 'reseller',
        is_active    => 1,
        billing_data => 1,
    };
    ($res, $content) = $test_machine->request_post($reseller_admin, '/api/admins/');
    $test_machine->http_code_msg(201, "create a reseller admin for the csv tests", $res, $content);
    my $reseller_admin_uri = $res->header('Location');

    #$fake_data must not be used until runas('admin'), it would act as the reseller
    $test_machine->set_reseller_credentials($reseller_admin);
    $test_machine->runas('reseller');
    $test_machine->content_type->{POST} = 'text/csv';

    #without the reseller_id column
    ($res, $content) = $test_machine->request_post(
        "res1_$t,100,2037-01-01,\n", '/api/vouchers/?purge_existing=true');
    $test_machine->http_code_msg(201, "check csv upload with purge_existing as reseller", $res, $content);
    my (undef, $list) = $test_machine->request_get('/api/vouchers/?page=1&rows=100');
    is_deeply([map { $_->{code} } grep { defined $_ } @{ $test_machine->get_embedded_forcearray($list) }],
        ["res1_$t"], "check the reseller only has the voucher it uploaded");

    $test_machine->runas('admin');
    ok(exists $vouchers_of->($other_reseller_id)->{"resother_$t"},
        "check the reseller purge kept the voucher of the other reseller");
    is_deeply([sort keys %{ $vouchers_of->($reseller_id) }], ["res1_$t"],
        "check the reseller purge deleted its own vouchers only");

    #request_delete checks the 204 itself
    $test_machine->request_delete('/api/vouchers/'.$vouchers_of->($other_reseller_id)->{"resother_$t"}->{id});
    $test_machine->request_delete('/api/vouchers/'.$vouchers_of->($reseller_id)->{"res1_$t"}->{id});
    $test_machine->request_delete($reseller_admin_uri);

    $test_machine->content_type->{POST} = 'application/json';
}

done_testing;

# vim: set tabstop=4 expandtab:
