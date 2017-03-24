use strict;
use warnings;

use Test::More;
use Test::Collection;

my $test_machine = Test::Collection->new(
    name => 'calls',
);

diag('Note that the next tests require at least one subscriber to be present');

SKIP:
{ #MT#16171
    my ($res,$sub1,$sub1_id,$sub1_user,$sub1_pass,$cl_collection, $cl_collection_in, $cl_collection_out);

    ($res, $sub1) = $test_machine->check_item_get('/api/subscribers/?page=1&rows=1&order_by=id&order_by_direction=desc',"fetch a subscriber for testing");
    if ($sub1->{total_count} < 1) {
        skip("Precondition not met: need a subscriber",1);
    }
    ($sub1_id) = $sub1->{_embedded}->{'ngcp:subscribers'}->[0]->{_links}{self}{href} =~ m!subscribers/([0-9]*)$!;

    cmp_ok ($sub1_id, '>', 0, "should be positive integer");
    
    ($res, $cl_collection) = $test_machine->check_item_get('/api/calls/?page=1&rows=10&subscriber_id='.$sub1_id,"fetch calls collection of subscriber ($sub1_id) by filter");
    
    diag("Total number of calls: " . $cl_collection->{total_count});
    
}

done_testing;

# vim: set tabstop=4 expandtab:
