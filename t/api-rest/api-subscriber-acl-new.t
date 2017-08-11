#!/usr/bin/perl -w
use strict;

use NGCP::Test;
use Test::More;
use JSON qw/from_json to_json/;
use Data::Dumper;

my $test = NGCP::Test->new();
my $t = $test->generate_sid();
my $c = $test->client();

my $ref = $test->reference_data(
    client => $c,
    use_persistent => 1,
    delete_persistent => 0,
    depends => [
        {
            resource => 'billingprofiles',
            hints => [{ name => 'customer billingprofile' }],
            name => 'my_billprof'
        },
        {
            resource => 'domains',
            name => 'my_domain'
        },
        {
            resource => 'customercontacts',
            name => 'my_contact'
        },
        {
            resource => 'customers',
            name => 'my_foreign_customer',
            hints => [{ field => 'type', value => 'pbxaccount' }],
        },
        {
            resource => 'customers',
            name => 'my_filled_customer',
            hints => [{ name => 'filled pbxaccount customer' }],
        },
        {
            resource => 'subscribers',
            name => 'my_foreign_pilot',
            hints => [{ name => 'pbx pilot subscriber'}]
        }
    ],
);

# first, create a pbx customer to work with
my $customer_res = $test->resource(
    client => $c,
    resource => 'customers',
    data => { 
        billing_profile_id => $ref->data('my_billprof')->{id},
        contact_id => $ref->data('my_contact')->{id},
        status => 'active',
        type => 'pbxaccount',
    },
    autodelete_created_items => 1,
);
$customer_res->test_post(
    name => 'create helper customer',
    expected_result => { 'code' => 201 }
);
my $customer = $customer_res->pop_created_item();


# define a reference subscriber pbx
my $sub_res = $test->resource(
    client => $c,
    resource => 'subscribers',
    data => { 
        customer_id => $customer->{id},
        domain_id => $ref->data('my_domain')->{id},
        username => "user_$t",
        password => "pass_$t",
        webusername => "webuser_$t",
        webpassword => "webpass_$t",
        # TODO: why do we have to explicitly set this to create a pilot?
        # should be set automatically on creation of first subscriber
        # in pbx customer, no?
        is_pbx_pilot => 0,
        is_pbx_group => 0,
        administrative => 0,
        primary_number => { cc => '43', ac => '999', sn => $t },
        pbx_extension => undef,
        display_name => "Admin Pilot $t",
        status => 'active',
    },
    #print_summary_on_finish => 1,
    autodelete_created_items => 1,
);

my $num_res = $test->resource(
    client => $c,
    resource => 'numbers',
);

$sub_res->test_post(
    name => 'create subscribers',
    data_replace => [
        [
            # a pilot with administrative rights
            { field => 'administrative', value => 1 },
            { field => 'is_pbx_pilot', value => 1 },
            { field => 'username', value => "pilot_user_$t" },
            { field => 'password', value => "pilot_pass_$t" },
            { field => 'webusername', value => "pilot_webuser_$t" },
            { field => 'webpassword', value => "pilot_webpass_$t" },
            { field => 'alias_numbers', value =>
                [map { { cc => '43', ac => '888', sn => sprintf("$t%d", $_) } } (0 .. 9)]
            }
        ],
        [
            # an extension with administrative rights
            { field => 'administrative', value => 1 },
            { field => 'primary_number', delete => 1 },
            { field => 'pbx_extension', value => '101' },
            { field => 'username', value => "subadm_user_$t" },
            { field => 'password', value => "subadm_pass_$t" },
            { field => 'webusername', value => "subadm_webuser_$t" },
            { field => 'webpassword', value => "subadm_webpass_$t" },
        ],
        [
            # an extension without rights
            { field => 'primary_number', delete => 1 },
            { field => 'pbx_extension', value => '102' },
            { field => 'username', value => "subext_user_$t" },
            { field => 'password', value => "subext_pass_$t" },
            { field => 'webusername', value => "subext_webuser_$t" },
            { field => 'webpassword', value => "subext_webpass_$t" },
        ]
    ],
    skip_test_fields => [qw/alias_numbers.number_id primary_number.number_id/],
    expected_result => { code => 201 }
);
my $sub_ext = $sub_res->pop_created_item();
my $subadm_ext = $sub_res->pop_created_item();
my $subadm_pilot = $sub_res->pop_created_item();

# time to create clients to access the API with the individual subs
my $c_sub_ext = $test->client(
    role => 'subscriber',
    username => $sub_ext->{webusername} . '@' . $ref->data('my_domain')->{domain},
    password => $sub_ext->{webpassword},
);
my $c_subadm_ext = $test->client(
    role => 'subscriber',
    username => $subadm_ext->{webusername} . '@' . $ref->data('my_domain')->{domain},
    password => $subadm_ext->{webpassword},
);
my $c_subadm_pilot = $test->client(
    role => 'subscriber',
    username => $subadm_pilot->{webusername} . '@' . $ref->data('my_domain')->{domain},
    password => $subadm_pilot->{webpassword},
);
my $items;

# test working with subscribers with a subscriber without rights
{
    $sub_res->client($c_sub_ext);
    my $name = 'unprivileged subscriber get';
    # remove stuff from reference data which we don't expect in result
    my @blacklist = (qw/
        customer_id contract_id domain_id
        password webpassword
        uuid lock status
        create_timestamp modify_timestamp
    /);
    foreach my $k(@blacklist) {
        delete $sub_ext->{$k};
    }
    $items = $sub_res->test_get(
        name => $name,
        item => $sub_ext,
        expected_links => [qw/
            ngcp:reminders ngcp:voicemailsettings ngcp:callforwards
            ngcp:subscriberpreferences
        /],
        expected_fields => [qw/
            id domain administrative
            primary_number alias_numbers pbx_extension
            display_name email
            pbx_group_ids is_pbx_pilot is_pbx_group 
            username webusername
        /],
        expected_result => { code => 200 }
    );
    # TODO: by configuration, we should control whether passwords are present or not!

    # check if creating/modifying subscribers is forbidden
    $sub_res->test_post(
        name => 'create subscriber without privileges',
        expected_result => { 
            code => '403',
            error_re => 'Read-only resource for authenticated role'
        },
    );
    $sub_res->test_put(
        name => 'modify-put subscriber without privileges',
        item => $sub_ext,
        expected_result => { 
            code => '403',
            error_re => 'Read-only resource for authenticated role'
        },
    );
    $sub_res->test_patch(
        name => 'modify-patch subscriber without privileges',
        item => $sub_ext,
        data_replace => { field => 'username', value => 'test', op => 'replace' },
        expected_result => { 
            code => '403',
            error_re => 'Read-only resource for authenticated role'
        },
    );

    # test fetching numbers
    $num_res->client($c_sub_ext);
    $num_res->test_get(
        name => 'get numbers as unprivileged subscriber',
        expected_result => { 'code' => 403 }
    );
    # fake a numbers item and fetch it
    $num_res->test_get(
        name => 'get numbers item as unprivileged subscriber',
        item => { id => 999, cc => '43', ac => '999', sn => '999', subscriber_id => $c_sub_ext->{id} },
        expected_result => { 'code' => 403 }
    );

    # check if we can't access customers
    $customer_res->client($c_sub_ext);
    $customer_res->test_get(
        name => 'get own customer as unprivileged subscriber',
        item => $customer,
        expected_result => { 'code' => 403 }
    );
    $customer_res->test_get(
        name => 'get foreign customer as unprivileged subscriber',
        item => $ref->data('my_foreign_customer'),
        expected_result => { 'code' => 403 }
    );
}

# test working with subscribers with a subscriberadmin
{
    $sub_res->client($c_subadm_ext);
    my $name = 'subadmin subscriber get';
    my @blacklist = (qw/
        contract_id domain_id
        password webpassword
        uuid lock status
        create_timestamp modify_timestamp
    /);
    foreach my $k(@blacklist) {
        delete $subadm_ext->{$k};
    }

    # get own subscriber
    $items = $sub_res->test_get(
        name => $name,
        item => $subadm_ext,
        expected_links => [qw/
            ngcp:reminders ngcp:voicemailsettings ngcp:callforwards
            ngcp:subscriberpreferences ngcp:customers
        /],
        expected_result => { code => 200 }
    );
    my $item = pop @{ $items };
    foreach my $k(@blacklist) {
        ok(!exists $item->{$k}, "$name - absence of $k");
        $test->inc_test_count();
    }
    # TODO: by configuration, we should control whether passwords are present or not!

    # TODO: get sub_ext subscriber

    # TODO: get all subscribers of customer

    # check if creating/modifying subscribers is ok
    $sub_res->test_post(
        name => 'create subscribers as subadmin',
        data_replace => [
            [
                # a pilot with administrative rights
                { field => 'administrative', value => 1 },
                { field => 'is_pbx_pilot', value => 1 },
                { field => 'username', value => "pilot_user_subadm_$t" },
                { field => 'password', value => "pilot_pass_subadm_$t" },
                { field => 'webusername', value => "pilot_webuser_subadm_$t" },
                { field => 'webpassword', value => "pilot_webpass_subadm_$t" },
            ],
            [
                # an extension with administrative rights
                { field => 'administrative', value => 1 },
                { field => 'primary_number', delete => 1 },
                { field => 'pbx_extension', value => '201' },
                { field => 'username', value => "subadm_user_subadm_$t" },
                { field => 'password', value => "subadm_pass_subadm_$t" },
                { field => 'webusername', value => "subadm_webuser_subadm_$t" },
                { field => 'webpassword', value => "subadm_webpass_subadm_$t" },
            ],
            [
                # an extension without rights
                { field => 'primary_number', delete => 1 },
                { field => 'pbx_extension', value => '202' },
                { field => 'username', value => "subext_user_subadm_$t" },
                { field => 'password', value => "subext_pass_subadm_$t" },
                { field => 'webusername', value => "subext_webuser_subadm_$t" },
                { field => 'webpassword', value => "subext_webpass_subadm_$t" },
            ],
            [
                # an extension in another customer
                { field => 'primary_number', delete => 1 },
                { field => 'pbx_extension', value => '203' },
                { field => 'username', value => "subext_user_foreign_$t" },
                { field => 'password', value => "subext_pass_foreign_$t" },
                { field => 'webusername', value => "subext_webuser_foreign_$t" },
                { field => 'webpassword', value => "subext_webpass_foreign_$t" },
                { field => 'customer_id', value => $ref->data('my_foreign_customer')->{id} },
            ]
        ],
        expected_result => [
            { code => 422, error_re => 'Customer already has a pbx pilot subscriber.' },
            { code => 201 },
            { code => 201 },
            { code => 201 }, # this must be checked below whether customer_id is properly set
        ],
        skip_test_fields => [qw/customer_id/], # ... so don't check explicitly here
        expected_fields => [qw/
            id customer_id domain administrative
            primary_number alias_numbers pbx_extension
            display_name email
            pbx_group_ids is_pbx_pilot is_pbx_group 
            username webusername
        /],
    );
    $item = $sub_res->pop_created_item();
    is($item->{customer_id}, $subadm_ext->{customer_id},
        "subscribers - create subscribers as subadmin - foreign customer overridden");
    $test->inc_test_count();
    my $sub_ext_2 = $item;
    $sub_res->push_created_item($sub_ext_2);

    # can we change own subscriber?
    $sub_res->test_put(
        name => 'modify-put subscriber as subadmin',
        item => $subadm_ext,
        expected_result => { 
            code => '403',
            error_re => 'Read-only resource for authenticated role'
        },
    );
    $sub_res->test_patch(
        name => 'modify-patch subscriber as subadmin',
        item => $subadm_ext,
        data_replace => { field => 'username', value => 'test', op => 'replace' },
        expected_result => { 
            code => '403',
            error_re => 'Read-only resource for authenticated role'
        },
    );

    # can we change other subscriber?
    $sub_res->test_put(
        name => 'modify-put other subscriber as subadmin',
        item => $sub_ext,
        expected_result => { 
            code => '403',
            error_re => 'Read-only resource for authenticated role'
        },
    );
    $sub_res->test_patch(
        name => 'modify-patch other subscriber as subadmin',
        item => $sub_ext,
        data_replace => { field => 'username', value => 'test', op => 'replace' },
        expected_result => { 
            code => '403',
            error_re => 'Read-only resource for authenticated role'
        },
    );


    # can we fetch subscriber details of foreign customer?
    $items = $sub_res->test_get(
        name => 'fetch subscribers of foreign customer',
        query_params => [{ customer_id => $ref->data('my_filled_customer')->{id} }],
        expected_count => 0,
        expected_result => { code => 200 }
    );
    # TODO: the above should actually return an error instead of an empty customer?

    # test fetching numbers
    $num_res->client($c_subadm_ext);
    $items = $num_res->test_get(
        name => 'get numbers as privileged subscriber',
        expected_links => [qw/ngcp:subscribers/],
        expected_fields => [qw/id ac cc sn subscriber_id is_primary/],
        skip_test_fields => [qw/is_primary/], # don't check explicitly here
        expected_result => { 'code' => 200 }
    );
    my $num_item = pop @{ $items };
    my ($num_item_primary, $num_item_alias);
    foreach my $num(@{ $num_item->{_embedded}->{'ngcp:numbers'} }) {
        if(!$num_item_primary && $num->{is_primary}) {
            $num_item_primary = $num;
        } elsif(!$num_item_alias) {
            $num_item_alias = $num;
        }
        last if($num_item_primary && $num_item_alias);
    }
    $num_res->test_put(
        name => 'move primary number from pilot to ext',
        item => $num_item_primary,
        data_replace => {field => 'subscriber_id', value => $sub_ext->{id}},
        expected_result => { code => 422, error_re => 'Cannot reassign primary number'},
    );
    $num_res->test_put(
        name => 'move alias number from pilot to ext',
        item => $num_item_alias,
        data_replace => {field => 'subscriber_id', value => $sub_ext->{id}},
        expected_result => { code => 200 },
    );
    $num_res->test_put(
        name => 'move alias number from ext to ext',
        item => $num_item_alias,
        data_replace => {field => 'subscriber_id', value => $sub_ext_2->{id}},
        expected_result => { code => 200 },
    );
    $num_res->test_put(
        name => 'move alias number from ext to pilot',
        item => $num_item_alias,
        data_replace => {field => 'subscriber_id', value => $subadm_ext->{id}},
        expected_result => { code => 200 },
    );

    $num_res->client($c_sub_ext);
    $items = $num_res->test_get(
        name => 'individual number fetch as ext',
        item => $num_item_alias,
        expected_result => { code => 403 }
    );
    $num_res->client($c_subadm_ext);

    # move back to ext again, and check if it's moved to pilot on ext termination
    $num_res->test_put(
        name => 'move alias number from pilot to ext again',
        item => $num_item_alias,
        data_replace => {field => 'subscriber_id', value => $sub_ext->{id}},
        expected_result => { code => 200 }
    );
    $sub_res->client($c_sub_ext);
    $sub_res->test_delete(
        name => 'terminate extension as unprivileged sub',
        item => $sub_ext_2,
        expected_result => { code => 403 }
    );
    $sub_res->client($c_subadm_ext);

    $sub_res->test_delete(
        name => 'terminate extension as subadmin',
        item => $sub_ext,
        expected_result => { code => 204 }
    );
    $items = $num_res->test_get(
        name => 'number assignment after ext delete',
        item => $num_item_alias,
        expected_links => [qw/ngcp:subscribers/],
        expected_result => { code => 200 }
    );
    $item = pop @{ $items };
    is($item->{subscriber_id}, $subadm_pilot->{id}, "subscribers - number subscriber after ext delete");
    $test->inc_test_count;

    # test deletion of own subscriber
    $sub_res->test_delete(
        name => 'terminate own subadmin as subadmin',
        item => $subadm_ext,
        expected_result => { code => 403, error_re => 'Cannot terminate own subscriber' }
    );
    # test deletion of pilot subscriber
    $sub_res->test_delete(
        name => 'terminate pilot subscriber as subadmin',
        item => $subadm_pilot,
        expected_result => { code => 403, error_re => 'Cannot terminate pilot subscriber' }
    );

    # can we (not) move number to foreign sub?
    $num_res->test_put(
        name => 'move number to foreign subscriber',
        item => $num_item_alias,
        data_replace => { field => 'subscriber_id', value => $ref->data('my_foreign_pilot')->{id}},
        expected_result => { code => 422, error_re => "Invalid 'subscriber_id', does not exist" }
    );

    # check if we can access own customer but not foreign
    $customer_res->client($c_subadm_ext);
    $customer_res->test_get(
        name => 'get own customer as privileged subscriber',
        item => $customer,
        expected_links => [],
        expected_result => { 'code' => 200 },

    );
    $customer_res->test_get(
        name => 'get foreign customer as privileged subscriber',
        item => $ref->data('my_foreign_customer'),
        expected_result => { 'code' => 403 }
    );
}

# TODO: more tests for unprivileged subscriber!

$sub_res->push_created_item($subadm_pilot);
$sub_res->push_created_item($subadm_ext);
$customer_res->push_created_item($customer);

$sub_res->client($c);
$customer_res->client($c);

$test->done();

