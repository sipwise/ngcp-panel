use warnings;
use strict;

use Test::More;

use DDP;

use_ok('NGCP::Panel::Utils::API');

my $empty_result = NGCP::Panel::Utils::API::generate_swagger_datastructure(
    {}, 'admin',
);

basic_result_check($empty_result);

my $collections1 = {
    admins => {
        actions => [ "GET", "HEAD", "OPTIONS", "POST" ],
        config => {}, # unused currently
        description => "Defines admins to log into the system via panel or api.",
        entity_name => "Admin",
        fields      => [
            {   description   => "Billing data",
                name          => "billing_data",
                readonly      => undef,
                type_original => "Boolean",
                types         => [ "null", "Boolean" ]
            },
        ],
        item_actions => [ "DELETE", "GET", "HEAD", "OPTIONS" ],
        journal_resource_config => {},         # unused currently
        name                    => "Admins",
        properties              => {},
        query_params            => [
            {   description => "Filter for admins belonging to a specific reseller",
                param => "reseller_id",
            },
        ],
        sorting_cols => [ "id", "reseller_id", ],
        uploads      => [],     # unused currently
        uri => "/api/admins/",  # unused currently
    },
};

my $result1 = NGCP::Panel::Utils::API::generate_swagger_datastructure(
    $collections1, 'admin',
);

basic_result_check($result1);

ok(exists($result1->{paths}{'/admins/'}), "Collection Path for admins exists");
ok(exists($result1->{paths}{'/admins/{id}'}), "Item Path for admins exists");

ok(exists($result1->{paths}{'/admins/'}{get}), "Collection Path for admins has get");
ok(exists($result1->{paths}{'/admins/'}{post}), "Collection Path for admins has post");
ok(exists($result1->{paths}{'/admins/{id}'}{get}), "Item Path for admins has get");

ok(exists($result1->{components}{schemas}{Admin}), "Schema for Admin exists");
is($result1->{components}{schemas}{Admin}{type}, 'object', "Schema for Admin content check");
is($result1->{components}{schemas}{Admin}{properties}{billing_data}{type}, 'boolean', "Schema for Admin content check");

done_testing;

sub basic_result_check {
    my ($res) = @_;

    ok(exists($res->{info}), "Info Object exists");
    ok(exists($res->{openapi}), "OpenAPI Object exists");
    ok(exists($res->{paths}), "Paths Object exists");
    ok(exists($res->{components}), "Components Object exists");

    is ($res->{openapi}, '3.0.0', 'Check OpenAPI version');
    is ($res->{info}{title}, 'NGCP API', 'Check NGCP info');
    return;
}

