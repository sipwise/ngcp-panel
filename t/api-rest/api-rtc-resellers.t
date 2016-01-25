use strict;
use warnings;

use Test::More;
use Test::Collection;
use Test::FakeData;
use Data::Dumper;


my $fake_data = Test::FakeData->new;
$fake_data->set_data_from_script({
    'resellers' => {
        'data' => {
            name => "apitest reseller name " . time(),
            contract_id => sub { return shift->create('contracts', @_); },
            status => 'active',
            enable_rtc => 1,  # JSON::false
            rtc_networks => ['sip', 'xmpp', 'sipwise'],
        },
    },
});

my $test_machine = Test::Collection->new(
    name => 'resellers',
    embedded_resources => [qw/resellers/],
);
$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};
# store some basic reseller data, to run tests with
$test_machine->DATA_ITEM_STORE($fake_data->process('resellers'));
$test_machine->form_data_item( );

my $reseller_id;

# test reseller API
{
    my ($res, $content) = $test_machine->check_item_get('/api/resellers/?page=1&rows=10', "fetch resellers collection");
    my $req;
    ($res, $content, $req) = $test_machine->check_item_post();
    is($res->code, 201, 'create test reseller successful');
    #my $reseller_id = $test_machine->get_id_from_created($res);
    ($reseller_id) = $res->header('Location') =~ m/(\d+)$/;

    cmp_ok($reseller_id, '>', 0, 'got valid reseller id');
    ($res, $content) = $test_machine->check_item_get("/api/resellers/$reseller_id/", "fetch created reseller");
    is($res->code, 200, 'reseller successfully retrieved');
    ok($content->{enable_rtc}, 'rtc is enabled on created reseller');
}

# test rtcnetworks API
{
    my ($res, $content) = $test_machine->check_item_get("/api/rtcnetworks/$reseller_id", "fetch rtcnetwork");
    is($res->code, 200, 'rtcnetwork successfully retrieved');
    isa_ok($content->{networks}, 'ARRAY', 'networks arrayref exists');
    is(scalar(@{ $content->{networks} }), 3, 'should contain the 3 precreated networks');
    is($content->{networks}[0]{connector}, 'sip-connector', 'First network is of "sip-connector"');

    ($res, $content) = $test_machine->request_patch(
            [
                { op => 'remove', path => '/networks/2'},
                { op => 'replace', path => '/networks/1/connector', value => 'webrtc'},
            ],
            "/api/rtcnetworks/$reseller_id/",
        );
    is($res->code, 200, 'PATCH operation on rtcnetworks item');
    isa_ok($content->{networks}, 'ARRAY', 'networks arrayref exists');
    is(scalar(@{ $content->{networks} }), 2, 'should be left with 2 networks');
    is($content->{networks}[1]{connector}, 'webrtc', 'Changed one network to "webrtc"');
}

{
    my ($res, $content, $req) = $test_machine->request_patch(
            [
                { op => 'replace', path => '/status', value => 'terminated' },
            ],
            "/api/resellers/$reseller_id/",
        );
    is($res->code, 200, 'terminate reseller successful');
}
$test_machine->clear_test_data_all();

done_testing;

1;

# vim: set tabstop=4 expandtab:
