#!/usr/bin/perl -w
use strict;

use NGCP::Test;
use Test::More;
use Clone 'clone';
use JSON qw/from_json to_json/;
use Data::Dumper;

my $test = NGCP::Test->new(log_debug => 1);
my $t = $test->generate_sid();
my $c_admin = $test->client();

my $ref = $test->reference_data(
    client => $c_admin,
    use_persistent => 1,
    delete_persistent => 0,
    depends => [
        {
            resource => 'admins',
            hints => [{ name => 'reseller admin' }],
            name => 'my_reseller_admin'
        },
        {
            resource => 'admins',
            hints => [{ name => 'rtc reseller admin' }],
            name => 'my_rtcreseller_admin'
        },
    ],
);

my $sid = $ref->sid();

# test capabilities as admin
diag("test capabilities as admin");
{
    my $expected = {
        cloudpbx => $ENV{HAS_CLOUDPBX} // 0,
        sms => $ENV{HAS_SMS} // 0,
        faxserver => $ENV{HAS_FAXSERVER} // 1,
        rtcengine => $ENV{HAS_RTCENGINE} // 0,
        fileshare => $ENV{HAS_FILESHARE} // 0,
        mobilepush => $ENV{HAS_MOBILEPUSH} // 0,
    };

    my $cap_res = $test->resource(
        client => $c_admin,
        resource => 'capabilities',
    );

    my $caps = $cap_res->test_get(
        name => 'fetch capabilities as admin',
        expected_links => [],
        expected_fields => [qw/
            id name enabled
        /],
        expected_result => { code => 200 }
    );

    my $tmpexpected = clone($expected);
    my @caps = ();
    foreach my $cap (@{ $caps->[0]->{_embedded}->{'ngcp:capabilities'} }) {
        my $name = $cap->{name};
        my $val = $cap->{enabled} ? 1 : 0;
        is(exists $expected->{$name}, 1, "returned admin capability $name is expected");
        $test->inc_test_count();
        is($val, $expected->{$name}, "returned admin capability $name has value $$expected{$name}");
        $test->inc_test_count();
        delete $tmpexpected->{$cap->{name}};
        push @caps, $cap;
    }
    is(keys %{ $tmpexpected }, 0, "all expected admin capabilities seen");
    $test->inc_test_count();

    foreach my $cap(@caps) {
        diag("test individual capability $cap->{name} with id $cap->{id} as admin");
        my $items = $cap_res->test_get(
            name => "fetch individual capability $cap->{name} as admin",
            item => $cap,
            expected_links => [],
            expected_fields => [qw/
                id name enabled
            /],
            expected_result => { code => 200 }
        );
    }
}

# test capabilities as reseller without rtcengine enabled
diag("test capabilities as reseller without rtcengine");
{
    my $c_reseller = $test->client(
        role => 'reseller',
        username => $ref->data('my_reseller_admin')->{login},
        password => "reseller_$sid",
    );

    my $expected = {
        cloudpbx => $ENV{HAS_CLOUDPBX} // 0,
        sms => $ENV{HAS_SMS} // 0,
        faxserver => $ENV{HAS_FAXSERVER} // 1,
        rtcengine => 0,
        fileshare => $ENV{HAS_FILESHARE} // 0,
        mobilepush => $ENV{HAS_MOBILEPUSH} // 0,
    };

    my $cap_res = $test->resource(
        client => $c_reseller,
        resource => 'capabilities',
    );

    my $caps = $cap_res->test_get(
        name => 'fetch capabilities as reseller',
        expected_links => [],
        expected_fields => [qw/
            id name enabled
        /],
        expected_result => { code => 200 }
    );

    my $tmpexpected = clone($expected);
    my @caps = ();
    foreach my $cap (@{ $caps->[0]->{_embedded}->{'ngcp:capabilities'} }) {
        my $name = $cap->{name};
        my $val = $cap->{enabled} ? 1 : 0;
        is(exists $expected->{$name}, 1, "returned reseller capability $name is expected");
        $test->inc_test_count();
        is($val, $expected->{$name}, "returned reseller capability $name has value $$expected{$name}");
        $test->inc_test_count();
        delete $tmpexpected->{$cap->{name}};
        push @caps, $cap;
    }
    is(keys %{ $tmpexpected }, 0, "all expected reseller capabilities seen");
    $test->inc_test_count();

    foreach my $cap(@caps) {
        diag("test individual capability $cap->{name} with id $cap->{id} as reseller");
        my $items = $cap_res->test_get(
            name => "fetch individual capability $cap->{name} as reseller",
            item => $cap,
            expected_links => [],
            expected_fields => [qw/
                id name enabled
            /],
            expected_result => { code => 200 }
        );
    }
}

# test capabilities as reseller with rtcengine enabled
diag("test capabilities as reseller with rtcengine");
{
    my $c_rtcreseller = $test->client(
        role => 'reseller',
        username => $ref->data('my_rtcreseller_admin')->{login},
        password => "rtcreseller_$sid",
    );

    my $expected = {
        cloudpbx => $ENV{HAS_CLOUDPBX} // 0,
        sms => $ENV{HAS_SMS} // 0,
        faxserver => $ENV{HAS_FAXSERVER} // 1,
        rtcengine => $ENV{HAS_RTCENGINE} // 1,
        fileshare => $ENV{HAS_FILESHARE} // 0,
        mobilepush => $ENV{HAS_MOBILEPUSH} // 0,
    };

    my $cap_res = $test->resource(
        client => $c_rtcreseller,
        resource => 'capabilities',
    );

    my $caps = $cap_res->test_get(
        name => 'fetch capabilities as rtc reseller',
        expected_links => [],
        expected_fields => [qw/
            id name enabled
        /],
        expected_result => { code => 200 }
    );

    my $tmpexpected = clone($expected);
    my @caps = ();
    foreach my $cap (@{ $caps->[0]->{_embedded}->{'ngcp:capabilities'} }) {
        my $name = $cap->{name};
        my $val = $cap->{enabled} ? 1 : 0;
        is(exists $expected->{$name}, 1, "returned rtc reseller capability $name is expected");
        $test->inc_test_count();
        is($val, $expected->{$name}, "returned rtc reseller capability $name has value $$expected{$name}");
        $test->inc_test_count();
        delete $tmpexpected->{$cap->{name}};
        push @caps, $cap;
    }
    is(keys %{ $tmpexpected }, 0, "all expected rtc reseller capabilities seen");
    $test->inc_test_count();

    foreach my $cap(@caps) {
        diag("test individual capability $cap->{name} with id $cap->{id} as rtc reseller");
        my $items = $cap_res->test_get(
            name => "fetch individual capability $cap->{name} as rtc reseller",
            item => $cap,
            expected_links => [],
            expected_fields => [qw/
                id name enabled
            /],
            expected_result => { code => 200 }
        );
    }
}

diag("test capabilities as nonpbx nonrtc customer");
{
    my $c_subscriber = $test->client(
        role => 'subscriber',
        username => $ref->data('my_nonpbxnonrtc_subscriber')->{webusername} . '@' .
                    $ref->data('my_nonpbxnonrtc_subscriber')->{domain},
        password => $ref->data('my_nonpbxnonrtc_subscriber')->{webpassword},
    );

    my $expected = {
        cloudpbx => 0,
        sms => $ENV{HAS_SMS} // 0,
        faxserver => $ENV{HAS_FAXSERVER} // 1,
        rtcengine => 0, 
        fileshare => $ENV{HAS_FILESHARE} // 0,
        mobilepush => $ENV{HAS_MOBILEPUSH} // 0,
    };

    my $cap_res = $test->resource(
        client => $c_subscriber,
        resource => 'capabilities',
    );

    my $caps = $cap_res->test_get(
        name => 'fetch capabilities as nonpbx nonrtc subscriber',
        expected_links => [],
        expected_fields => [qw/
            id name enabled
        /],
        expected_result => { code => 200 }
    );

    my $tmpexpected = clone($expected);
    my @caps = ();
    foreach my $cap (@{ $caps->[0]->{_embedded}->{'ngcp:capabilities'} }) {
        my $name = $cap->{name};
        my $val = $cap->{enabled} ? 1 : 0;
        is(exists $expected->{$name}, 1, "returned nonpbx nonrtc capability $name is expected");
        $test->inc_test_count();
        is($val, $expected->{$name}, "returned nonpbx nonrtc capability $name has value $$expected{$name}");
        $test->inc_test_count();
        delete $tmpexpected->{$cap->{name}};
        push @caps, $cap;
    }
    is(keys %{ $tmpexpected }, 0, "all expected nonpbx nonrtc capabilities seen");
    $test->inc_test_count();

    foreach my $cap(@caps) {
        diag("test individual capability $cap->{name} with id $cap->{id} as nonpbx nonrtc subscriber");
        my $items = $cap_res->test_get(
            name => "fetch individual capability $cap->{name} as nonrtc nonpbx reseller",
            item => $cap,
            expected_links => [],
            expected_fields => [qw/
                id name enabled
            /],
            expected_result => { code => 200 }
        );
    }
}

$test->done();
