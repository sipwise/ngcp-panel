use strict;
use warnings;

use Test::More;
use Test::Collection;
use Test::FakeData;
use Data::Dumper;
use Clone qw/clone/;

my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'callforwards' => {
        'data' => {
            #not really necessary - there isn't POST method
            #subscriber_id  => sub { return shift->get_id('subscribers',@_); },
            cfu => {
                destinations => [
                    { destination => "12345", timeout => 200},
                ],
                times => undef,
            },
            cft => {
                destinations => [
                    { destination => "5678" },
                    { destination => "voicebox", timeout => 500 },
                ],
                ringtimeout => 10,
            },
            cfb => {
                destinations => [
                    {
                        destination => "customhours",
                        priority => "1",
                        timeout => "300"
                    },
                    {
                        destination => "officehours",
                        priority => "2",
                        timeout => "300"
                    },
                    {
                        destination => "customhours",
                        priority => "1",
                        timeout => "300",
                        announcement_id => sub { return shift->get_id('soundhandles_custom_announcements',@_); },
                    },
                ],
                sources => [
                    {
                        source => "123-13-13"
                    }
                ],
                'times' => [
                    {
                       hour => "18-8",
                       mday =>  undef,
                       minute => "0-0",
                       month => undef,
                       wday => "6-2",
                       year => undef
                    }
                ]
            },
        },
    },
});

my $test_machine = Test::Collection->new(
    name => 'callforwards',
    embedded_resources => [qw/subscribers callforwards/],
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};
$test_machine->DATA_ITEM_STORE($fake_data->process('callforwards'));
$test_machine->form_data_item( );

my $announcement_id = $test_machine->DATA_ITEM->{cfb}->{destinations}->[2]->{announcement_id};
ok($announcement_id =~/^\d+$/,"announcement_id should be a positiv integer: $announcement_id");


SKIP:{
    my ($res,$req,$content);
    my $cf1 = $test_machine->get_item_hal();

    if(!$cf1->{total_count} && !$cf1->{content_collection}->{total_count}){
        skip("Testing requires at least one present callforward. No creation is available.",1);
    }

    $test_machine->check_bundle();
    my $cf1_id = $test_machine->get_id_from_hal($cf1->{content_collection}); #($cf1,'callforwards');
    cmp_ok ($cf1_id, '>', 0, "should be positive integer");
    my $cf1single_uri = "/api/callforwards/$cf1_id";
    my $cf1single;
    (undef, $cf1single) = $test_machine->check_item_get($cf1single_uri,"fetch cf id $cf1_id");

    #check cf structure
    delete $cf1single->{_links};
    is(ref $cf1single, "HASH", "cf should be hash");
    my @valid_types = (qw/cfu cfb cft cfna cfs/);
    my %valid_types;
    @valid_types{@valid_types} = ( 1 ) x @valid_types;
    foreach my $type(@valid_types){
        ok(exists $cf1single->{$type}, "cf should have key $type");
    }
    foreach my $test_type (keys %{$cf1single}){
        ok( exists $valid_types{$test_type} , "check cf against unknown types: $test_type");
    }

    #write cf and check written values
    my($cf1_put,$cf1_get) = $test_machine->check_put2get({data_in => $test_machine->DATA_ITEM, uri => $cf1single_uri},undef, 1 );
    is (ref $cf1_put->{content}, "HASH", "should be hashref");
    is ($cf1_put->{content}->{cfu}{destinations}->[0]->{timeout}, 200, "Check timeout of cft");
    is ($cf1_put->{content}->{cft}{destinations}->[0]->{simple_destination}, "5678", "Check first destination of cft");
    like ($cf1_put->{content}->{cft}{destinations}->[0]->{destination}, qr/^sip:5678@/, "Check first destination of cft (regex, full uri)");
    is ($cf1_put->{content}->{cft}{destinations}->[1]->{destination}, "voicebox", "Check second destination of cft");
    is ($cf1_put->{content}->{cfb}{destinations}->[0]->{destination}, "customhours", "Check customhours destination");
    is ($cf1_put->{content}->{cfb}{destinations}->[1]->{destination}, "officehours", "Check customhours destination");

    is ($cf1_put->{content}->{cfb}{destinations}->[2]->{announcement_id}, $announcement_id, "Check announcement_id after put");
    is ($cf1_get->{content}->{cfb}{destinations}->[2]->{announcement_id}, $announcement_id, "Check announcement_id after get");


    #write invalid 'timeout'
    ($res,$content,$req) = $test_machine->request_put({
        cfu => {
            destinations => [
                { destination => "12345", timeout => "foobar"},
            ],
            times => undef,
        },
    }, $cf1single_uri);
    $test_machine->http_code_msg(422, "create callforward with invalid timeout", $res, $content);
    is($content->{code}, "422", "check error code in body");
    like($content->{message}, qr/Validation failed/, "check error message in body");

    # get invalid cf
    ($res, $content) = $test_machine->request_get("/api/callforwards/abc");
    is($res->code, 400, "try invalid callforward id");
    is($content->{code}, "400", "check error code in body");
    like($content->{message}, qr/Invalid id/, "check error message in body");

    my($cf2_put,$cf2_get) = $test_machine->check_put2get({data_in => clone($cf1_put->{content}), uri => $cf1single_uri},undef, 1 );
    is_deeply($cf1_put->{content}, $cf2_put->{content}, "check put if unmodified put returns the same");
    $test_machine->check_embedded($cf2_put->{content});

    my $mod_cf1;
    ($res,$mod_cf1) = $test_machine->check_patch_correct( [ { op => 'replace', path => '/cfu/destinations/0/timeout', value => '123' } ] );
    is($mod_cf1->{cfu}{destinations}->[0]->{timeout}, "123", "check patched replace op");

    ($res,$mod_cf1) = $test_machine->request_patch( [ { op => 'add', path => '/cfu/destinations/-', value => {destination => 99999} } ] );
    is($res->code, 200, "check patch, add a cfu destination");

    ($res,$mod_cf1) = $test_machine->request_patch( [ { op => 'replace', path => '/cfu/destinations/0/timeout', value => "" } ] );
    is($res->code, 422, "check patched undef timeout");

    ($res,$mod_cf1) = $test_machine->request_patch( [ { op => 'replace', path => '/cfu/destinations/0/timeout', value => 'invalid' } ] );
    is($res->code, 422, "check patched invalid status");

    #5954
    my $data = {
        destinations => [
            {
                destination => "officehours",
                timeout => "15",
                announcement_id =>  $announcement_id,
            },
        ],
    };
    ($res,$content,$req) = $test_machine->request_put({
        data_in => {
            cfu => $data,
        },
        uri => $cf1single_uri,
    });
    is ($content->{cfu}->{destinations}->[0]->{announcement_id}, undef, "Check announcement_id after put into other destination (officehours)");
    #$test_machine->http_code_msg(422, "Check announcement_id for the officehours", $res, $content);#got 200 here

    $data->{destinations}->[0]->{destination} = 'customhours';
    ($res,$content,$req) = $test_machine->request_put({ cfu => $data}, $cf1single_uri );
    is($content->{cfu}->{destinations}->[0]->{announcement_id}, $announcement_id, "Check announcement_id after put into correct destination (customhours)");


    foreach my $destination (qw/officehours customhours/){
        $data->{destinations}->[0]->{destination} = $destination;
        #$data->{destinations}->[0]->{destination} = 'customhours';

        $data->{destinations}->[0]->{announcement_id} = 9999999;
        ($res,$content,$req) = $test_machine->request_put({ cfu => $data}, $cf1single_uri);
        $test_machine->http_code_msg(422, "Check absent announcement_id", $res, $content);

        $data->{destinations}->[0]->{announcement_id} = 'aaaaa';
        ($res,$content,$req) = $test_machine->request_put({ cfu => $data}, $cf1single_uri);
        $test_machine->http_code_msg(422, "Check invalid announcement_id", $res, $content);

        my $wrong_announcement_hal = $test_machine->get_item_hal('soundhandles', '/api/soundhandles/?group=pbx');
        $data->{destinations}->[0]->{announcement_id} = $wrong_announcement_hal->{content}->{id};
        ($res,$content,$req) = $test_machine->request_put({ cfu => $data }, $cf1single_uri );
        $test_machine->http_code_msg(422, "Check announcement_id from other group", $res, $content);
    }

    #return initial state:
    $test_machine->request_put( $cf1single, $cf1single_uri );
}

done_testing;

1;

# vim: set tabstop=4 expandtab:
