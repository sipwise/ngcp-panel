use strict;
use warnings;

use Test::More;
use Test::Collection;
use Test::FakeData;
use Data::Dumper;

my $test_machine = Test::Collection->new(
    name => 'cfdestinationsets',
    QUIET_DELETION => 1,
);
my $fake_data = Test::FakeData->new;

$test_machine->methods->{collection}->{allowed} = {map {$_ => 1} qw(GET HEAD OPTIONS POST)};
$test_machine->methods->{item}->{allowed}       = {map {$_ => 1} qw(GET HEAD OPTIONS PUT PATCH DELETE)};

$fake_data->set_data_from_script({
    'cfdestinationsets' => {
        data => {
            destinations => [
                {
                   destination =>  "officehours",
                   priority => 1,
                   timeout => 300,
                },
                #without announcement
                {
                   destination =>  "officehours",
                   priority => 1,
                   timeout => 300,
                }
            ],
            name => "Weekend days",
            subscriber_id => sub { return shift->get_id('subscribers',@_); },
        },
    },
});

$test_machine->DATA_ITEM_STORE($fake_data->process('cfdestinationsets'));
$test_machine->form_data_item( );

# create 3 new billing zones from DATA_ITEM
$test_machine->check_create_correct( 3, sub{ $_[0]->{name} .= $_[1]->{i} ; } );
$test_machine->check_get2put();
$test_machine->check_bundle();

diag('Note that the next tests require at least one subscriber to be present ' .
    'and accessible to the current API user.');

# fetch a cfdestinationset for testing that
{
    my ($res, $content) = $test_machine->check_item_get('/api/cfdestinationsets/?page=1&rows=10', "fetch cfdestinationsets collection");
    ($res, $content) = $test_machine->check_item_get('/api/cftimesets/?page=1&rows=10', "fetch cftimesets collection");
}

# fetch a cfdestinationset being a reseller
SKIP:
{
    my ($res,$sub1,$cf_collection1,$cft_collection1,$cf_collection2,$cft_collection2);
    
    $test_machine->runas('reseller');
    
    ($res, $cf_collection1) = $test_machine->request_get('/api/cfdestinationsets/?page=1&rows=10');
    if ($res->code == 401) { # Authorization required
        skip("Couldn't login as reseller", 1);
    }
    is($res->code, 200, "fetch cfdestinationsets collection as reseller");

    ($res, $cft_collection1) = $test_machine->check_item_get('/api/cftimesets/?page=1&rows=10', "fetch cftimesets collection as reseller");

    ($res, $sub1) = $test_machine->check_item_get('/api/subscribers/?page=1&rows=1',"fetch a subscriber of our reseller for testing");
    if ($sub1->{total_count} < 1) {
        skip("Precondition not met: need a subscriber",1);
    }
    my ($sub1_id) = $sub1->{_embedded}->{'ngcp:subscribers'}->{_links}{self}{href} =~ m!subscribers/([0-9]*)$!;
    cmp_ok ($sub1_id, '>', 0, "should be positive integer");


    ($res, $cf_collection2) = $test_machine->check_item_get('/api/cfdestinationsets/?page=1&rows=10&subscriber_id='.$sub1_id, "fetch cfdestinationsets collection as reseller with subscriber filter");

    cmp_ok($cf_collection1->{total_count}, '>=', $cf_collection2->{total_count},
        "filtered collection (cfdestinationsets) should be smaller or equal");

    # --------

    ($res, $cft_collection2) = $test_machine->check_item_get('/api/cftimesets/?page=1&rows=10&subscriber_id='.$sub1_id, "fetch cftimesets collection as reseller with subscriber filter");

    cmp_ok($cft_collection1->{total_count}, '>=', $cft_collection2->{total_count},
        "filtered collection (cftimesets) should be smaller or equal");
}

{
    $test_machine->runas('admin');
    
    my($res, $content) = $test_machine->request_get('/api/callforwards/99987');
    is($res->code, 404, "check get nonexistent callforwards item");

    ($res, $content) = $test_machine->request_get('/api/cfdestinationsets/99987');
    is($res->code, 404, "check get nonexistent cfdestinationsets item");

    ($res, $content) = $test_machine->request_get('/api/cftimesets/99987');
    is($res->code, 404, "check get nonexistent cftimesets item");

    ($res, $content) = $test_machine->request_post(sub{$_[0]->{destinations}->[0]->{simple_destination}= 'aaa@bbb.com';});
    is($res->code, 201, "check creation with simple_destination");
}

#$fake_data->clear_test_data_all();
$test_machine->clear_test_data_all();
undef $fake_data;
undef $test_machine;
done_testing;

# vim: set tabstop=4 expandtab:
