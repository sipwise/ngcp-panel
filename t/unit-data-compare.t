#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use Data::Compare;
use JSON;

my $origin = {
    num => 123,
    string => "foobar",
    true_val => !!1,
    false_val => !1,
    json_true => JSON::true,
    json_false => JSON::false,
};

my $same = {
    num => 123,
    string => "foobar",
    true_val => !!1,
    false_val => !1,
    json_true => JSON::true,
    json_false => JSON::false,    
};

my $diff_num = {
    num => 999,
    string => "foobar",
    true_val => !!1,
    false_val => !1,
    json_true => JSON::true,
    json_false => JSON::false,
};

my $diff_string = {
    num => 123,
    string => "aaaa",
    true_val => !!1,
    false_val => !1,
    json_true => JSON::true,
    json_false => JSON::false,
};

my $diff_bool = {
    num => 123,
    string => "foobar",
    true_val => !1,
    false_val => !!1,
    json_true => JSON::true,
    json_false => JSON::false,
};

my $diff_json = {
    num => 123,
    string => "foobar",
    true_val => !1,
    false_val => !!1,
    json_true => JSON::false,
    json_false => JSON::true,
};

diag("Test::More only checks using is_deeply");
is_deeply($same, $origin);

TODO: {
    local $TODO = "The following tests must fail";

    is_deeply($diff_num, $origin);
    is_deeply($diff_string, $origin);
    is_deeply($diff_bool, $origin);
    is_deeply($diff_json, $origin);
}

diag("The same checks, this time using Data::Compare");
ok(Data::Compare::Compare($same, $origin));
ok(!Data::Compare::Compare($diff_num, $origin));
ok(!Data::Compare::Compare($diff_string, $origin));
ok(!Data::Compare::Compare($diff_bool, $origin));

# note: this fails with Data::Compare@1.23 due to a bug, which has been fixed in 1.25
ok(!Data::Compare::Compare($diff_json, $origin));

done_testing();
