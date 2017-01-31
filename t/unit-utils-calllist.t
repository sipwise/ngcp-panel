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

# # Scenario 4
# {
#     my $cdr1 = NGCP::Schema->resultset('cdr')->new_result({});
#     my $cdr2 = NGCP::Schema->resultset('cdr')->new_result({});
#     my $cdr3 = NGCP::Schema->resultset('cdr')->new_result({});
#     # p $cdr1;
#     # p $c->loc("foobar");
# }

done_testing;