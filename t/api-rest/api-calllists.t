use strict;
use warnings;

use Test::More;
use Test::Collection;

my $test_machine = Test::Collection->new(
    name => 'calllists',
);

diag('Note that the next tests require at least one subscriber to be present');

SKIP:
{
    my ($res,$sub1,$sub1_id,$cl_collection, $cl_collection_in, $cl_collection_out);

    if($ENV{API_FORCE_SUBSCRIBER_ID}) {
        $sub1_id = $ENV{API_FORCE_SUBSCRIBER_ID};
    } else {
        ($res, $sub1) = $test_machine->request_get('/api/subscribers/?page=1&rows=1');
        is($res->code, 200, "fetch a subscriber for testing");
        if ($sub1->{total_count} < 1) {
            skip("Precondition not met: need a subscriber",1);
        }
        ($sub1_id) = $sub1->{_embedded}->{'ngcp:subscribers'}->{_links}{self}{href} =~ m!subscribers/([0-9]*)$!;
    }
    cmp_ok ($sub1_id, '>', 0, "should be positive integer");
    
    ($res, $cl_collection) = $test_machine->request_get('/api/calllists/?page=1&rows=10&subscriber_id='.$sub1_id);
    is($res->code, 200, "fetch calllists collection of subscriber ($sub1_id)");

    ($res, $cl_collection_in) = $test_machine->request_get('/api/calllists/?page=1&rows=10&direction=in&subscriber_id='.$sub1_id);
    is($res->code, 200, "fetch calllists collection of subscriber ($sub1_id) with direction filter in");

    ($res, $cl_collection_out) = $test_machine->request_get('/api/calllists/?page=1&rows=10&direction=out&subscriber_id='.$sub1_id);
    is($res->code, 200, "fetch calllists collection of subscriber ($sub1_id) with direction filter out");

    is($cl_collection_in->{total_count}+$cl_collection_out->{total_count}, $cl_collection->{total_count},
        "Incoming and outgoing calls should add up to total number of calls");

    diag("Total number of calls: " . $cl_collection->{total_count});
}


done_testing;

# vim: set tabstop=4 expandtab:
