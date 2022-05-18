#!/usr/bin/perl
use strict;
use warnings;

use NGCP::Test;
use Test::More;
use Clone 'clone';
use JSON qw/from_json to_json/;
use Data::Dumper;

my $test = NGCP::Test->new(log_debug => 0);
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
            resource => 'subscriberprofiles',
            hints => [{ name => 'subscriber profile' }],
            name => 'my_sub_profile'
        },
        {
            resource => 'subscribers',
            hints => [{ name => 'pbx pilot subscriber' }],
            name => 'my_pbx_subscriber'
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

# test capabilities as reseller
diag("test capabilities as reseller");
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

diag("test capabilities as pbx subscriber");
{
    my $c_subscriber = $test->client(
        role => 'subscriber',
        username => $ref->data('my_pbx_subscriber')->{webusername} . '@' .
                    $ref->data('my_pbx_subscriber')->{domain},
        password => $ref->data('my_pbx_subscriber')->{webpassword},
    );

    my $expected = {
        cloudpbx => 1,
        sms => $ENV{HAS_SMS} // 0,
        faxserver => $ENV{HAS_FAXSERVER} // 1,
        fileshare => $ENV{HAS_FILESHARE} // 0,
        mobilepush => $ENV{HAS_MOBILEPUSH} // 0,
    };

    my $cap_res = $test->resource(
        client => $c_subscriber,
        resource => 'capabilities',
    );

    my $caps = $cap_res->test_get(
        name => 'fetch capabilities as pbx subscriber',
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
        is(exists $expected->{$name}, 1, "returned pbx capability $name is expected");
        $test->inc_test_count();
        is($val, $expected->{$name}, "returned pbx capability $name has value $$expected{$name}");
        $test->inc_test_count();
        delete $tmpexpected->{$cap->{name}};
        push @caps, $cap;
    }
    is(keys %{ $tmpexpected }, 0, "all expected pbx capabilities seen");
    $test->inc_test_count();

    foreach my $cap(@caps) {
        diag("test individual capability $cap->{name} with id $cap->{id} as pbx subscriber");
        my $items = $cap_res->test_get(
            name => "fetch individual capability $cap->{name} as pbx reseller",
            item => $cap,
            expected_links => [],
            expected_fields => [qw/
                id name enabled
            /],
            expected_result => { code => 200 }
        );
    }

    # get a subscriber profile assigned
    my $sub_res = $test->resource(
        client => $c_admin,
        resource => 'subscribers'
    );
    $sub_res->test_put(
        name => 'assign subscriber profile',
        item => $ref->data('my_pbx_subscriber'),
        skip_test_fields => [qw/modify_timestamp/],
        data_replace => [[
            {
                field => 'profile_set_id',
                value => $ref->data('my_sub_profile')->{profile_set_id},
            },
            {
                field => 'profile_id',
                value => $ref->data('my_sub_profile')->{id},
            },
        ]],
        expected_result => { code => '200' },
    );

    $caps = $cap_res->test_get(
        name => 'fetch capabilities as pbx subscriber after profile',
        expected_links => [],
        expected_fields => [qw/
            id name enabled
        /],
        expected_result => { code => 200 }
    );

    $expected->{faxserver} = $ENV{FAXSERVER}//1;
    $tmpexpected = clone($expected);
    @caps = ();
    foreach my $cap (@{ $caps->[0]->{_embedded}->{'ngcp:capabilities'} }) {
        my $name = $cap->{name};
        my $val = $cap->{enabled} ? 1 : 0;
        is(exists $expected->{$name}, 1, "returned pbx profile capability $name is expected");
        $test->inc_test_count();
        is($val, $expected->{$name}, "returned pbx profile capability $name has value $$expected{$name}");
        $test->inc_test_count();
        delete $tmpexpected->{$cap->{name}};
        push @caps, $cap;
    }
    is(keys %{ $tmpexpected }, 0, "all expected pbx profile capabilities seen");
    $test->inc_test_count();

    foreach my $cap(@caps) {
        diag("test individual pbx profile capability $cap->{name} with id $cap->{id} as pbx subscriber");
        my $items = $cap_res->test_get(
            name => "fetch individual pbx profile capability $cap->{name}",
            item => $cap,
            expected_links => [],
            expected_fields => [qw/
                id name enabled
            /],
            expected_result => { code => 200 }
        );
    }

    # modify profile to remove fax_server attribute
    my $prof_res = $test->resource(
        client => $c_admin,
        resource => 'subscriberprofiles'
    );
    my $orig_attrs = clone($ref->data('my_sub_profile')->{attributes});
    $prof_res->test_put(
        name => 'remove all attributes',
        item => $ref->data('my_sub_profile'),
        data_replace => {
            field => 'attributes', value => [qw/ncos clir/],
        },
        expected_result => { code => '200' },
    );


    # test again
    $caps = $cap_res->test_get(
        name => 'fetch capabilities as pbx subscriber after profile change',
        expected_links => [],
        expected_fields => [qw/
            id name enabled
        /],
        expected_result => { code => 200 }
    );

    $expected->{faxserver} = 0;
    $tmpexpected = clone($expected);
    @caps = ();
    foreach my $cap (@{ $caps->[0]->{_embedded}->{'ngcp:capabilities'} }) {
        my $name = $cap->{name};
        my $val = $cap->{enabled} ? 1 : 0;
        is(exists $expected->{$name}, 1, "returned pbx profile change capability $name is expected");
        $test->inc_test_count();
        is($val, $expected->{$name}, "returned pbx profile change capability $name has value $$expected{$name}");
        $test->inc_test_count();
        delete $tmpexpected->{$cap->{name}};
        push @caps, $cap;
    }
    is(keys %{ $tmpexpected }, 0, "all expected pbx profile change capabilities seen");
    $test->inc_test_count();

    foreach my $cap(@caps) {
        diag("test individual pbx profile change capability $cap->{name} with id $cap->{id} as pbx subscriber");
        my $items = $cap_res->test_get(
            name => "fetch individual pbx profile change capability $cap->{name}",
            item => $cap,
            expected_links => [],
            expected_fields => [qw/
                id name enabled
            /],
            expected_result => { code => 200 }
        );
    }

    # reset profile
    $sub_res->test_put(
        name => 'unassign subscriber profile',
        item => $ref->data('my_pbx_subscriber'),
        skip_test_fields => [qw/modify_timestamp/],
        data_replace => [[
            { field => 'profile_set_id', value => undef },
            { field => 'profile_id', value => undef },
        ]],
        expected_result => { code => '200' },
    );
    $prof_res->test_put(
        name => 'restore profile attributes',
        item => $ref->data('my_sub_profile'),
        data_replace => {
            field => 'attributes', value => $orig_attrs,
        },
        expected_result => { code => '200' },
    );
}

$test->done();
