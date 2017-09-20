#!/usr/bin/perl -w
use strict;

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
            hints => [{ name => 'superuser admin' }],
            name => 'my_super_admin'
        },
        {
            resource => 'admins',
            hints => [{ name => 'readonly admin' }],
            name => 'my_ro_admin'
        },
        {
            resource => 'admins',
            hints => [{ name => 'master reseller admin' }],
            name => 'my_reseller_admin'
        },
        {
            resource => 'admins',
            hints => [{ name => 'nomaster reseller admin' }],
            name => 'my_std_admin'
        },
    ],
);

my $sid = $ref->sid();

my $c_su_admin = $test->client(
    role => 'admin',
    username => $ref->data('my_super_admin')->{login},
    password => "superadmin_$sid",
);
my $c_ro_admin = $test->client(
    role => 'admin',
    username => $ref->data('my_ro_admin')->{login},
    password => "roadmin_$sid",
);
my $c_res_admin = $test->client(
    role => 'admin',
    username => $ref->data('my_reseller_admin')->{login},
    password => "mstreselleradmin_$sid",
);
my $c_std_admin = $test->client(
    role => 'admin',
    username => $ref->data('my_std_admin')->{login},
    password => "stdreselleradmin_$sid",
);


### let's roll

my $adm_res = $test->resource(
    client => $c_su_admin,
    resource => 'admins',
    data => {
        login => "testadmin_$sid",
        password => "testadmin_$sid",
        reseller_id => $ref->data('my_super_admin')->{reseller_id},
    },
);

# superuser can fetch all admins
my $admins = $adm_res->test_get(
    name => 'fetch all admins as superuser',
    expected_links => [qw/
        ngcp:resellers
    /],
    expected_result => { code => '200' }
);

# superuser can create admin in own reseller
# superuser can create admin in other reseller
# superuser can't create admin with login > 31 chars
$adm_res->test_post(
    name => 'create reseller as su admin',
    data_replace => [
        {},
        [
            { field => 'reseller_id', value => $ref->data('my_reseller_admin')->{reseller_id} },
            { field => 'login', value => "o_res_admin_$sid" }
        ],
        { field => 'login', value => "some_overly_long_admin_$sid" }
    ],
    skip_test_fields => [qw/password/],
    expected_result => [
        { code => '201' },
        { code => '201' },
        { code => '422', error_re => 'Field should not exceed 31 characters' }
    ],
);

my $adm = $adm_res->pop_created_item();

# superuser can update admin in own reseller
$adm_res->test_put(
    name => 'update own reseller admin as su admin',
    item => $adm,
    data_replace => {
        field => 'login', value => "s_up_admin_$sid"
    },
    skip_test_fields => [qw/password/],
    expected_result => { code => '404' }
);

# superuser can delete admin in own reseller
$adm_res->test_delete(
    name => 'delete own reseller admin as su admin',
    item => $adm,
    expected_result => { code => '204' }
);

$adm = $adm_res->pop_created_item();

# superuser can update admin in other reseller
$adm_res->test_put(
    name => 'update other reseller admin as su admin',
    item => $adm,
    data_replace => {
        field => 'login', value => "another_updated_admin_$sid"
    },
    expected_result => { code => '404' }
);

# superuser can delete admin in other reseller
$adm_res->test_delete(
    name => 'delete other reseller admin as su admin',
    item => $adm,
    expected_result => { code => '204' }
);

# superuser can't delete self
$adm_res->test_delete(
    name => 'delete self as su admin',
    item => $ref->data('my_super_admin'),
    expected_result => { code => '403' }
);

### read-only tests

$adm_res->client($c_ro_admin);

# ro admin can fetch all admins
$admins = $adm_res->test_get(
    name => 'fetch all admins as ro admin',
    expected_links => [],
    expected_result => { code => '200' }
);

my @admins = @{ $admins->[0]->{_embedded}->{'ngcp:admins'} };
foreach my $a(@admins) {
    is($a->{reseller_id}, undef,
        "ro-fetched admin belongs to own reseller");
    $test->inc_test_count();
}

# ro admin can't create admin
$adm_res->test_post(
    name => 'create reseller as ro admin',
    data_replace => [
        { field => 'login', value => "roadm_$sid" }
    ],
    expected_result => [
        { code => '403' },
    ],
);

# ro admin can't update own admin
$adm_res->test_put(
    name => 'update self as ro admin',
    item => $ref->data('my_ro_admin'),
    data_replace => {
        field => 'login', value => "up_adm_$sid"
    },
    expected_result => { code => '404' }
);

# ro admin can't update other admin
$adm_res->test_put(
    name => 'update self as ro admin',
    item => $ref->data('my_reseller_admin'),
    data_replace => {
        field => 'login', value => "up_adm_$sid"
    },
    expected_result => { code => '404' }
);

# ro admin can't delete other admin
$adm_res->test_delete(
    name => 'delete reseller admin as ro admin',
    item => $ref->data('my_reseller_admin'),
    expected_result => { code => '403' }
);

# ro admin can't delete self
$adm_res->test_delete(
    name => 'delete self as ro admin',
    item => $ref->data('my_ro_admin'),
    expected_result => { code => '403' }
);

### reseller admin tests

$adm_res->client($c_res_admin);

# res admin can fetch all admins
$admins = $adm_res->test_get(
    name => 'fetch all admins as reseller admin',
    expected_links => [],
    expected_result => { code => '200' }
);

@admins = @{ $admins->[0]->{_embedded}->{'ngcp:admins'} };
foreach my $a(@admins) {
    is($a->{reseller_id}, undef,
        "reseller-fetched admin belongs to own reseller");
    $test->inc_test_count();
}

# reseller admin can create admin
$adm_res->test_post(
    name => 'create reseller as reseller admin',
    data_replace => [
        { field => 'login', value => "resadm_$sid" }
    ],
    skip_test_fields => [qw/reseller_id password/],
    expected_result => [
        { code => '201' },
    ],
);
$adm = $adm_res->pop_created_item();

# reseller admin can update own admin
$adm_res->test_put(
    name => 'update self as reseller admin',
    item => $ref->data('my_reseller_admin'),
    data_replace => {
        field => 'login', value => "up_adm_$sid"
    },
    expected_result => { code => '404' }
);

# reseller admin can update other admin
$adm_res->test_put(
    name => 'update other as reseller admin',
    item => $ref->data('my_reseller_admin'),
    data_replace => {
        field => 'login', value => "up_adm_$sid"
    },
    expected_result => { code => '404' }
);

# reseller admin can delete other admin
$adm_res->test_delete(
    name => 'delete reseller admin as reseller admin',
    item => $adm,
    expected_result => { code => '204' }
);

# reseller admin can't delete other admin in foreign reseller
$adm_res->test_delete(
    name => 'delete other reseller admin as reseller admin',
    item => $ref->data('my_ro_admin'),
    expected_result => { code => '404' }
);

# reseller admin can't delete self
$adm_res->test_delete(
    name => 'delete self as reseller admin',
    item => $ref->data('my_reseller_admin'),
    expected_result => { code => '403' }
);

$adm_res->test_get(
    name => 'fetch other admin as reseller admin',
    item => $ref->data('my_std_admin'),
    skip_test_fields => [qw/is_superuser lawful_intercept reseller_id/],
    expected_result => { code => '200' }
);

$adm_res->test_get(
    name => 'fetch other reseller admin as reseller admin',
    item => $ref->data('my_ro_admin'),
    expected_result => { code => '404' }
);

### standard reseller without master tests

$adm_res->client($c_std_admin);

# std admin can only fetch self
$admins = $adm_res->test_get(
    name => 'fetch all admins as reseller',
    expected_links => [],
    expected_result => { code => '200' }
);
is($admins->[0]->{total_count}, 1, "check if only own admin is returned");
$test->inc_test_count();

@admins = @{ $admins->[0]->{_embedded}->{'ngcp:admins'} };
foreach my $a(@admins) {
    is($a->{id}, $ref->data('my_std_admin')->{id},
        "std reseller-fetched admin is self");
    $test->inc_test_count();
}

# std admin can't create admin
$adm_res->test_post(
    name => 'create admin as std admin',
    data_replace => [
        { field => 'login', value => "resadm_$sid" }
    ],
    expected_result => [
        { code => '403' },
    ],
);

# reseller admin can update own admin
$adm_res->test_put(
    name => 'update self as std admin',
    item => $ref->data('my_std_admin'),
    data_replace => {
        field => 'login', value => "up_adm_$sid"
    },
    expected_result => { code => '404' }
);

# reseller admin can update other admin
$adm_res->test_put(
    name => 'update other as std admin',
    item => $ref->data('my_reseller_admin'),
    data_replace => {
        field => 'login', value => "up_adm_$sid"
    },
    expected_result => { code => '404' }
);

# reseller admin can't delete other admin
$adm_res->test_delete(
    name => 'delete reseller admin as std admin',
    item => $ref->data('my_reseller_admin'),
    expected_result => { code => '404' }
);
$adm_res->test_delete(
    name => 'delete other reseller admin as std admin',
    item => $ref->data('my_ro_admin'),
    expected_result => { code => '404' }
);

# reseller admin can't delete self
$adm_res->test_delete(
    name => 'delete self as reseller admin',
    item => $ref->data('my_std_admin'),
    expected_result => { code => '403' }
);

$adm_res->test_get(
    name => 'fetch other admin as std admin',
    item => $ref->data('my_reseller_admin'),
    expected_result => { code => '404' }
);

$adm_res->test_get(
    name => 'fetch other reseller admin as std admin',
    item => $ref->data('my_ro_admin'),
    expected_result => { code => '404' }
);

$test->done();
