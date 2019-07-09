#!/usr/bin/perl
use strict;
use warnings;

use NGCP::Test;
use Test::More;
use JSON qw/from_json to_json/;
use Data::Dumper;

my $test = NGCP::Test->new(log_debug => 1);
my $t = $test->generate_sid();
my $c = $test->client();

my $ref = $test->reference_data(
    client => $c,
    use_persistent => 1,
    delete_persistent => 0,
    depends => [
        {
            resource => 'subscribers',
            name => 'my_seat_subscriber',
            hints => [{ name => 'pbx seat subscriber'}]
        }
    ],
);

my $dom = $ref->data('my_seat_subscriber')->{domain};
my $c_sub_ext = $test->client(
    role => 'subscriber',
    username =>
        $ref->data('my_seat_subscriber')->{webusername} . '@' . $dom,
    password => $ref->data('my_seat_subscriber')->{webpassword},
);

diag("test destination set as subscriber");
my $cf_dstset = $test->resource(
    client => $c_sub_ext,
    resource => 'cfdestinationsets',
    data => {
        name => 'test cf destination set',
        destinations => [
            # TODO: we have to define all fields here to pass deep testing
            { destination => "sip:12340\@$dom", timeout => 180, priority => 1, announcement_id => undef, simple_destination => '12340' },
            { destination => "sip:12341\@$dom", timeout => 180, priority => 2, announcement_id => undef, simple_destination => '12341' },
            { destination => "sip:12342\@$dom", timeout => 180, priority => 3, announcement_id => undef, simple_destination => '12342' },
        ],
    },
);

$cf_dstset->test_post(
    name => 'create destination sets',
    expected_result => { 'code' => 201 },
);

my $dstset = $cf_dstset->pop_created_item();

$cf_dstset->test_put(
    name => "test update",
    item => $dstset,
    data_replace => {
        field => 'destinations', value => [
            { destination => "sip:22340\@$dom", timeout => 180, priority => 1, announcement_id => undef, simple_destination => '22340' },
            { destination => "sip:22341\@$dom", timeout => 180, priority => 2, announcement_id => undef, simple_destination => '22341' },
            { destination => "sip:22342\@$dom", timeout => 180, priority => 3, announcement_id => undef, simple_destination => '22342' },
        ],
    },
    expected_result => { code => 200 },
);

diag("test source set as subscriber");
my $cf_srcset = $test->resource(
    client => $c_sub_ext,
    resource => 'cfsourcesets',
    data => {
        name => 'test cf source set',
        mode => 'whitelist',
        sources => [
            { source => "1235*" },
            { source => "1236" },
            { source => "1237[1-5]" },
        ],
    },
);

$cf_srcset->test_post(
    name => 'create source sets',
    expected_result => { 'code' => 201 },
);

my $srcset = $cf_srcset->pop_created_item();

$cf_srcset->test_put(
    name => "test update",
    item => $srcset,
    data_replace => {
        field => 'mode', value => 'blacklist',
    },
    expected_result => { code => 200 },
);

diag("test time set as subscriber");
my $cf_timset = $test->resource(
    client => $c_sub_ext,
    resource => 'cftimesets',
    data => {
        name => 'test cf time set',
        times => [
            { year => "2017", month => undef, mday => undef, wday => undef, hour => undef, minute => undef },
            { year => "2018-2019", month => undef, mday => undef, wday => undef, hour => undef, minute => undef },
            { year => undef, month => undef, mday => "10-20", wday => undef, hour => undef, minute => undef },
        ],
    },
);

$cf_timset->test_post(
    name => 'create time sets',
    expected_result => { 'code' => 201 },
);

my $timset = $cf_timset->pop_created_item();

$cf_timset->test_put(
    name => "test update",
    item => $timset,
    data_replace => {
        field => 'times', value => [
            { year => "2020", month => undef, mday => undef, wday => undef, hour => undef, minute => undef },
        ]
    },
    expected_result => { code => 200 },
);

diag("test cf mappings");

my $cf_map = $test->resource(
    client => $c_sub_ext,
    resource => 'cfmappings',
    data => {
        cfu => [],
        cfb => [],
        cft => [],
        cfna => [],
        cfs => [],
        cfr => [],
        cfo => [],
        cft_ringtimeout => undef,
    }
);

my $mappings = $cf_map->test_get(
    name => 'prefetch cf mappings',
    expected_links => [qw/
        ngcp:subscribers
    /],
    expected_result => { 'code' => 200 },
);
my $mapping = $mappings->[0]->{_embedded}->{'ngcp:cfmappings'}->[0];

my $cfu = [{
    destinationset => $dstset->{name},
    destinationset_id => $dstset->{id},
    sourceset => $srcset->{name},
    sourceset_id => $srcset->{id},
    timeset => $timset->{name},
    timeset_id => $timset->{id},
}];

$mappings = $cf_map->test_put(
    name => "update cfmapping",
    item => $mapping,
    data_replace => {
        field => 'cfu', value  => $cfu,
    },
    expected_result => { code => 200 },
);
ok(@{ $mappings->[0]->{cfu} } > 0, "test size of postfetched cfu mapping");
$test->inc_test_count();

$cf_dstset->test_delete(
    name => "test delete",
    item => $dstset,
    expected_result => { code => 204 },
);
$cf_srcset->test_delete(
    name => "test delete",
    item => $srcset,
    expected_result => { code => 204 },
);
$cf_timset->test_delete(
    name => "test delete",
    item => $timset,
    expected_result => { code => 204 },
);

$cf_map->test_delete(
    name => "test delete",
    item => $mapping,
    expected_result => { code => 404 },
);

$mapping->{cfu} = [];
$mappings = $cf_map->test_get(
    name => "refetch cfmapping after delete",
    item => $mapping,
    expected_links => [qw/
        ngcp:subscribers
    /],
    expected_result => { code => 200 },
);

$test->done();
