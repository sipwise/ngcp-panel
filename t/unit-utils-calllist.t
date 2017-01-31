use warnings;
use strict;

use Test::More;
use Test::MockObject;
use NGCP::Panel::Utils::CallList;
use NGCP::Schema;

ok(1, "stub");

use DDP;

my $c = Test::MockObject->new();
$c->mock('loc', sub{shift; return shift;});
$c->mock('log', sub{return shift;});
$c->mock('warn', sub{shift; print STDERR shift . "\n"});

# my $schema = NGCP::Schema->connect({dsn => "dbi:SQLite:dbname=:memory:",
#     on_connect_do => [
#         "ATTACH DATABASE ':memory:' AS provisioning",
#         "ATTACH DATABASE ':memory:' AS billing",
#         "ATTACH DATABASE ':memory:' AS ngcp",
#         "ATTACH DATABASE ':memory:' AS kamailio",
#         "ATTACH DATABASE ':memory:' AS accounting",
#     ]});
# $schema->deploy;
my $schema = NGCP::Schema->connect;

$c->mock('model', sub{return $schema;});

# Scenario 1 (1 cdr, search by customer, subscriber terminated, outgoing)
{
    my $customer_a = $schema->resultset('contracts')->new_result({
        id => 21,
    });
    my $subscriber_a1 = $schema->resultset('voip_subscribers')->new_result({
        id => 31,
        contract => $customer_a,
        status => "terminated",
    });
    my $cdr1 = $schema->resultset('cdr')->new_result({
        id => 11,
        source_user_id => "a1",
        source_account_id => 21,
        source_user => "a1_user",
        source_domain => "a_domain",
        source_cli => "11",
        source_clir => 1,
        destination_user_id => 0,
        destination_account_id => 0,
        destination_user => "x_user",
        destination_domain => "x_domain",
        destination_user_in => "x_user",
        call_type => "call",
        call_status => "cancel",
        call_id => "aaa",
        rating_status => "ok",
        source_subscriber => $subscriber_a1,
        duration => 1,
    });

    my $result = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr1, {customer => $customer_a}, {});
    # p $result;

    is($result->{direction}, "out", "scenario 1 - direction is outgoing");
    ok(!$result->{intra_customer}, "scenario 1 - not intra customer");
    is($result->{type}, "call", "scenario 1 - type is call");
}

# Scenario 2 (1 cdr, search by customer, subscriber unavailable, incoming)
{
    my $customer_a = $schema->resultset('contracts')->new_result({
        id => 21,
    });
    my $subscriber_a1 = $schema->resultset('voip_subscribers')->new_result({
        id => 31,
        contract => $customer_a,
        status => "terminated",
        # provisioning_voip_subscriber => {},
        username => "a1",
        uuid => "a1_id",
    });
    my $cdr1 = $schema->resultset('cdr')->new_result({
        id => 11,
        source_user_id => 0,
        source_account_id => 0,
        source_user => "x_user",
        source_domain => "a_domain",
        source_cli => "999",
        destination_user_id => "a1_id",
        destination_account_id => 21,
        destination_user => "a1",
        destination_domain => "x_domain",
        destination_user_in => "a1",
        call_type => "call",
        call_status => "cancel",
        call_id => "aaa",
        rating_status => "ok",
        duration => 1,
    });

    my $result = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr1, {customer => $customer_a}, {});
    # p $result;

    is($result->{direction}, "in", "scenario 2 - direction is incoming");
    ok(!$result->{intra_customer}, "scenario 2 - not intra customer");
    is($result->{type}, "call", "scenario 2 - type is call");
}

# Scenario 3 (1 cdr, search by customer, intra customer, subscriber terminated)
{
    my $customer_a = $schema->resultset('contracts')->new_result({
        id => 21,
    });
    my $subscriber_a1 = $schema->resultset('voip_subscribers')->new_result({
        id => 31,
        contract => $customer_a,
        status => "terminated",
        # provisioning_voip_subscriber => {},
        username => "a1",
        uuid => "a1_id",
    });
    my $subscriber_a2 = $schema->resultset('voip_subscribers')->new_result({
        id => 32,
        contract => $customer_a,
        status => "terminated",
        # provisioning_voip_subscriber => {},
        username => "a2",
        uuid => "a2_id",
    });
    my $cdr1 = $schema->resultset('cdr')->new_result({
        id => 11,
        source_user_id => "a1_id",
        source_account_id => 21,
        source_user => "a1_user",
        source_domain => "a_domain",
        source_cli => "131",
        destination_user_id => "a2_id",
        destination_account_id => 21,
        destination_user => "a2_user",
        destination_domain => "a_domain",
        destination_user_in => "a2_user",
        call_type => "call",
        call_status => "cancel",
        call_id => "bbb",
        rating_status => "ok",
        duration => 1,
    });

    my $result = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr1, {customer => $customer_a}, {});
    # p $result;

    ok(!!$result->{intra_customer}, "scenario 3 - is intra_customer");
    is($result->{direction}, "out", "scenario 3 - direction is outgoing");
}

# Scenario 4 (A1 -> A2 -> A3 -> B1)
{
    my $customer_a = $schema->resultset('contracts')->new_result({
        id => 21,
    });
    my $customer_b = $schema->resultset('contracts')->new_result({
        id => 22,
    });
    my $subscriber_a1 = $schema->resultset('voip_subscribers')->new_result({
        id => 31,
        contract => $customer_a,
        status => "active",
        provisioning_voip_subscriber => {
            uuid => 'a1_id',
            id => 41,
            domain => {id => 9999},
        },
        username => "a1",
        uuid => "a1_id",
    });
    my $subscriber_a2 = $schema->resultset('voip_subscribers')->new_result({
        id => 32,
        contract => $customer_a,
        status => "active",
        provisioning_voip_subscriber => {
            uuid => 'a2_id',
            id => 42,
            domain => {id => 9999},
        },
        username => "a2",
        uuid => "a2_id",
    });
    my $subscriber_a3 = $schema->resultset('voip_subscribers')->new_result({
        id => 33,
        contract => $customer_a,
        status => "active",
        provisioning_voip_subscriber => {
            uuid => 'a3_id',
            id => 43,
            domain => {id => 9999},
        },
        username => "a3",
        uuid => "a3_id",
    });
    my $subscriber_b1 = $schema->resultset('voip_subscribers')->new_result({
        id => 34,
        contract => $customer_b,
        status => "active",
        provisioning_voip_subscriber => {
            uuid => 'b1_id',
            id => 44,
            domain => {id => 9999},
        },
        username => "b1",
        uuid => "b1_id",
    });
    my $cdr1 = $schema->resultset('cdr')->new_result({
        id => 11,
        source_user_id => "a1_id",
        source_account_id => 21,
        source_user => "a1_user",
        source_domain => "a_domain",
        source_cli => "131",
        source_subscriber => $subscriber_a1,
        destination_user_id => "a2_id",
        destination_account_id => 21,
        destination_user => "a2_user",
        destination_domain => "a_domain",
        destination_user_in => "a2_user",
        destination_subscriber => $subscriber_a2,
        call_type => "call",
        call_status => "ok",
        call_id => "cdr1",
        rating_status => "ok",
        duration => 1,
    });
    my $cdr2 = $schema->resultset('cdr')->new_result({
        id => 12,
        source_user_id => "a2_id",
        source_account_id => 21,
        source_user => "a2_user",
        source_domain => "a_domain",
        source_cli => "132",
        source_subscriber => $subscriber_a2,
        destination_user_id => "a3_id",
        destination_account_id => 21,
        destination_user => "a3_user",
        destination_domain => "a_domain",
        destination_user_in => "a3_user",
        destination_subscriber => $subscriber_a3,
        call_type => "cfu",
        call_status => "ok",
        call_id => "cdr2",
        rating_status => "ok",
        duration => 1,
    });
    my $cdr3 = $schema->resultset('cdr')->new_result({
        id => 13,
        source_user_id => "a3_id",
        source_account_id => 21,
        source_user => "a3_user",
        source_domain => "a_domain",
        source_cli => "133",
        source_subscriber => $subscriber_a3,
        destination_user_id => "b1_id",
        destination_account_id => 22,
        destination_user => "b1_user",
        destination_domain => "b_domain",
        destination_user_in => "b1_user",
        destination_subscriber => $subscriber_b1,
        call_type => "cfu",
        call_status => "ok",
        call_id => "cdr3",
        rating_status => "ok",
        duration => 1,
    });

    # Perspective A
    my $result1_a = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr1, {customer => $customer_a}, {});
    my $result2_a = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr2, {customer => $customer_a}, {});
    my $result3_a = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr3, {customer => $customer_a}, {});

    is($result1_a->{type}, "call",     "scenario 4, cdr1, perspective A - type is call");
    is($result1_a->{direction}, "out", "scenario 4, cdr1, perspective A - direction is out");
    ok(!!$result1_a->{intra_customer}, "scenario 4, cdr1, perspective A - intra_customer is true");

    is($result2_a->{type}, "cfu",      "scenario 4, cdr2, perspective A - type is cfu");
    is($result2_a->{direction}, "out", "scenario 4, cdr2, perspective A - direction is out");
    ok(!!$result2_a->{intra_customer}, "scenario 4, cdr2, perspective A - intra_customer is true");

    is($result3_a->{type}, "cfu",      "scenario 4, cdr3, perspective A - type is cfu");
    is($result3_a->{direction}, "out", "scenario 4, cdr3, perspective A - direction is out");
    ok( !$result3_a->{intra_customer}, "scenario 4, cdr3, perspective A - intra_customer is false");

    # Perspective A1
    my $result1_a1 = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr1, {customer => $customer_a, subscriber => $subscriber_a1}, {});

    is($result1_a1->{type}, "call",     "scenario 4, cdr1, perspective A1 - type is call");
    is($result1_a1->{direction}, "out", "scenario 4, cdr1, perspective A1 - direction is out");
    ok(!!$result1_a1->{intra_customer}, "scenario 4, cdr1, perspective A1 - intra_customer is true");

    # Perspective A2
    my $result1_a2 = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr1, {customer => $customer_a, subscriber => $subscriber_a2}, {});
    my $result2_a2 = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr2, {customer => $customer_a, subscriber => $subscriber_a2}, {});

    is($result1_a2->{type}, "call",     "scenario 4, cdr1, perspective A2 - type is call");
    is($result1_a2->{direction}, "in",  "scenario 4, cdr1, perspective A2 - direction is in");
    ok(!!$result1_a2->{intra_customer}, "scenario 4, cdr1, perspective A2 - intra_customer is true");

    is($result2_a2->{type}, "cfu",      "scenario 4, cdr2, perspective A2 - type is cfu");
    is($result2_a2->{direction}, "out", "scenario 4, cdr2, perspective A2 - direction is out");
    ok(!!$result2_a2->{intra_customer}, "scenario 4, cdr2, perspective A2 - intra_customer is true");


    # Perspective B
    my $result3_b = NGCP::Panel::Utils::CallList::process_cdr_item($c, $cdr3, {customer => $customer_b}, {});

    is($result3_b->{type}, "call",     "scenario 4, cdr3, perspective B - type is call");
    is($result3_b->{direction}, "in",  "scenario 4, cdr3, perspective B - direction is in");
    ok( !$result3_b->{intra_customer}, "scenario 4, cdr3, perspective B - intra_customer is false");
}

done_testing;
