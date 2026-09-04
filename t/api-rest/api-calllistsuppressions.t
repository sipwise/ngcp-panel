use strict;
use warnings;

use Test::Collection;
use Test::FakeData;
use Test::More;

#init test_machine
my $test_machine = Test::Collection->new(
    name => 'calllistsuppressions',
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'calllistsuppressions' => {
        data => {
            domain    => 'apitest.example.org',
            direction => 'outgoing',
            pattern   => '^431',
            mode      => 'obfuscate',
            label     => 'apitest',
        },
        'query' => ['domain','direction','mode'],
        'data_callbacks' => {
            'uniquizer_cb' => sub { Test::FakeData::string_uniquizer(\$_[0]->{domain}); },
        },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('calllistsuppressions'));
$test_machine->form_data_item( );

# create 3 new call list suppressions from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{pattern} .= $_[1]->{i} ; } );

# the domain filter supports "*" wildcards. this runs right after the creation,
# where the 3 items above are the only ones sharing DATA_ITEM_STORE's domain
{
    my $domain = $test_machine->DATA_ITEM_STORE->{domain};
    my ($head, $tail) = split(/\./, $domain, 2);

    my %expected = (
        #no wildcard at all still means an exact match
        $domain         => 3,
        "*$domain"      => 3,
        "$domain*"      => 3,
        "*$tail"        => 3,
        "$head*"        => 3,
        "*$head*"       => 3,
        "$head*$tail"   => 3,
        'nosuchdomain*' => 0,
        #no implicit trailing wildcard is added
        "$domain.*"     => 0,
    );

    foreach my $filter (sort keys %expected) {
        my ($res, $content) = $test_machine->request_get(
            '/api/calllistsuppressions/?page=1&rows=10&domain='.$filter);
        $test_machine->http_code_msg(200, "check domain filter '$filter'", $res, $content);
        is($content->{total_count}, $expected{$filter},
           "check domain filter '$filter' result count");
    }
}

$test_machine->check_get2put();
$test_machine->check_bundle();

# domain, direction and pattern have to be unique together
{
    my ($res, $err) = $test_machine->check_item_post(sub{ $_[0]->{pattern} .= 1; });
    is($res->code, 422, "create call list suppression with duplicate domain/direction/pattern");
    is($err->{code}, "422", "check error code in body");
    ok($err->{message} =~ /must be unique/, "check error message in body");
}

# an empty domain means any domain, and it is also the default
{
    #the domain is what the uniquizer varies, so uniquize the pattern instead to
    #keep the domain/direction/pattern triple unique across runs
    my ($res, $content) = $test_machine->check_item_post(sub{
        delete $_[0]->{domain};
        Test::FakeData::string_uniquizer(\$_[0]->{pattern});
    });
    is($res->code, 201, "create call list suppression without domain");
    is($content->{domain}, '', "check domain defaults to an empty string");
    #request_delete instead of check_item_delete: this item was not registered
    #by check_create_correct, so EXPECTED_AMOUNT_CREATED must stay untouched
    $test_machine->request_delete($res->header('Location'));
}

$test_machine->clear_test_data_all();

# csv upload and download. this runs after clear_test_data_all, so the table
# contains exactly the uploaded rows and the download can be compared literally
{
    my $csv_data = <<'EOS_CSV';
csvtest1.example.org,outgoing,^431,obfuscate,csv1
csvtest2.example.org,incoming,^432,filter,csv2
EOS_CSV

    $test_machine->content_type->{POST} = 'text/csv';

    my ($res, $content) = $test_machine->request_post(
        $csv_data, '/api/calllistsuppressions/?purge_existing=true');
    $test_machine->http_code_msg(201, "check csv upload", $res, $content);

    #the Accept header has to be exactly "text/csv", any addition to it falls
    #back to the usual collection listing
    my $req = $test_machine->get_request_get('/api/calllistsuppressions/');
    $req->header('Accept' => 'text/csv');
    ($res, $content) = $test_machine->request($req);
    $test_machine->http_code_msg(200, "check csv download", $res, $content);
    is($res->filename, 'call_list_suppressions.csv', "check downloaded csv filename");
    is($res->content, $csv_data, "check downloaded csv content");

    #the uploaded rows are out of the Collection control, the first upload of the
    #next block purges them

    #restore by assigning the value: content_type returns the hash reference
    #itself, so saving and setting it back again would be a no-op
    $test_machine->content_type->{POST} = 'application/json';
}

# a malformed csv has to be reported and not silently accepted
{
    $test_machine->content_type->{POST} = 'text/csv';

    #a row with a wrong number of columns
    my ($res, $err) = $test_machine->request_post(
        "csvtest3.example.org,outgoing,^433\n",
        '/api/calllistsuppressions/?purge_existing=true');
    $test_machine->http_code_msg(422, "check csv upload with a wrong column count", $res, $err);
    ok($err->{message} =~ /skipped the following line numbers: 1/,
        "check the skipped line number is reported");
    ok($err->{message} =~ /imported 0 row/, "check the imported amount is reported");

    #a row csv can't parse at all. it used to end the upload silently, dropping
    #the rest of the file and still reporting success
    my $csv_broken = <<'EOS_CSV';
csvtest4.example.org,outgoing,^434,obfuscate,csv4
csvtest5.example.org,outgoing,"^435,obfuscate,csv5
csvtest6.example.org,outgoing,^436,obfuscate,csv6
EOS_CSV
    ($res, $err) = $test_machine->request_post(
        $csv_broken, '/api/calllistsuppressions/?purge_existing=true');
    $test_machine->http_code_msg(422, "check csv upload with an unparseable row", $res, $err);
    ok($err->{message} =~ /skipped the following line numbers: 2/,
        "check the unparseable line number is reported");
    #the line after the broken one has to be imported anyway
    ok($err->{message} =~ /imported 2 row/, "check the lines after the broken one are imported");

    #leave no rows behind, they are out of the Collection control. the one field
    #line is rejected on purpose, this request is only done for the purge. an
    #empty body can't be used for it, as it is rejected with 400
    ($res, $err) = $test_machine->request_post(
        'purgeonly', '/api/calllistsuppressions/?purge_existing=true');
    $test_machine->http_code_msg(422, "check csv purge with a rejected row", $res, $err);

    $test_machine->content_type->{POST} = 'application/json';
}

done_testing;

# vim: set tabstop=4 expandtab:
