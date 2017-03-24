use strict;
use warnings;

use Test::More;
use Test::Collection;

my $test_machine = Test::Collection->new(
    name => 'calllists',
);

diag('Note that the next tests require at least one subscriber to be present');

# test with a subscriber
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
        ($sub1_id) = $sub1->{_embedded}->{'ngcp:subscribers'}->[0]->{_links}->{self}{href} =~ m!subscribers/([0-9]*)$!;
    }
    cmp_ok ($sub1_id, '>', 0, "should be positive integer");
    
    ($res, $cl_collection) = $test_machine->request_get('/api/calllists/?page=1&rows=10&subscriber_id='.$sub1_id);
    is($res->code, 200, "fetch calllists collection of subscriber ($sub1_id)");

    ($res, $cl_collection_in) = $test_machine->request_get('/api/calllists/?page=1&rows=10&direction=in&subscriber_id='.$sub1_id);
    is($res->code, 200, "fetch calllists collection of subscriber ($sub1_id) with direction filter in");

    ($res, $cl_collection_out) = $test_machine->request_get('/api/calllists/?page=1&rows=10&direction=out&subscriber_id='.$sub1_id);
    is($res->code, 200, "fetch calllists collection of subscriber ($sub1_id) with direction filter out");

    ok($cl_collection_in->{total_count} + $cl_collection_out->{total_count} >= $cl_collection->{total_count},
        "Incoming and outgoing calls should be greater than or equal to total number of calls");

    diag("Total number of calls: " . $cl_collection->{total_count});
}

# test with a customer
SKIP:
{
    my ($res,$cust1,$cust1_id,$cl_collection, $cl_collection_in, $cl_collection_out);

    if($ENV{API_FORCE_CUSTOMER_ID}) {
        $cust1_id = $ENV{API_FORCE_CUSTOMER_ID};
    } else {
        ($res, $cust1) = $test_machine->request_get('/api/customers/?page=1&rows=1');
        is($res->code, 200, "fetch a customer for testing");
        if ($cust1->{total_count} < 1) {
            skip("Precondition not met: need a customer",1);
        }
        ($cust1_id) = $cust1->{_embedded}->{'ngcp:customers'}->[0]->{_links}{self}{href} =~ m!customers/([0-9]*)$!;
    }
    cmp_ok ($cust1_id, '>', 0, "should be positive integer");
    
    ($res, $cl_collection) = $test_machine->request_get('/api/calllists/?page=1&rows=10&customer_id='.$cust1_id);
    is($res->code, 200, "fetch calllists collection of customer ($cust1_id)");

    ($res, $cl_collection_in) = $test_machine->request_get('/api/calllists/?page=1&rows=10&direction=in&customer_id='.$cust1_id);
    is($res->code, 200, "fetch calllists collection of customer ($cust1_id) with direction filter in");

    ($res, $cl_collection_out) = $test_machine->request_get('/api/calllists/?page=1&rows=10&direction=out&customer_id='.$cust1_id);
    is($res->code, 200, "fetch calllists collection of customer ($cust1_id) with direction filter out");

    ok($cl_collection_in->{total_count} + $cl_collection_out->{total_count} >= $cl_collection->{total_count},
        "Incoming and outgoing calls should be greater than or equal to total number of calls");

    diag("Total number of calls: " . $cl_collection->{total_count});
}

SKIP:
{ #MT#16171
    my ($res,$sub1,$sub1_id,$sub1_user,$sub1_pass,$cl_collection, $cl_collection_in, $cl_collection_out);

    ($res, $sub1) = $test_machine->check_item_get('/api/subscribers/?page=1&rows=1&order_by=id&order_by_direction=desc',"fetch a subscriber for testing");
    if ($sub1->{total_count} < 1) {
        skip("Precondition not met: need a subscriber",1);
    }
    ($sub1_id) = $sub1->{_embedded}->{'ngcp:subscribers'}->[0]->{_links}{self}{href} =~ m!subscribers/([0-9]*)$!;
    #$sub1_user = $sub1->{_embedded}->{'ngcp:subscribers'}->{'username'};
    #$sub1_pass = $sub1->{_embedded}->{'ngcp:subscribers'}->{'webpassword'} // '';

    cmp_ok ($sub1_id, '>', 0, "should be positive integer");
    
    ($res, $cl_collection) = $test_machine->check_item_get('/api/calls/?page=1&rows=10&subscriber_id='.$sub1_id,"fetch calls collection of subscriber ($sub1_id) by filter");
    
    diag("Total number of calls: " . $cl_collection->{total_count});
    
    #subscriber api login only works if panel session is established.
    
    #$test_machine = Test::Collection->new(
    #    name => 'subscriber_calls',
    #    runas_role => 'subscriber',
    #    subscriber_user => $sub1_user,
    #    subscriber_pass => $sub1_pass,
    #);
    
    #($res, $cl_collection) = $test_machine->check_item_get('/api/calls/?page=1&rows=10',"fetch calls collection of subscriber ($sub1_id) as subscriber");
    
    #diag("Total number of calls: " . $cl_collection->{total_count});
    
}

done_testing;

# vim: set tabstop=4 expandtab:
