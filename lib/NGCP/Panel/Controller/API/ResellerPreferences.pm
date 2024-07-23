package NGCP::Panel::Controller::API::ResellerPreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    required_licenses => [qw/reseller/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub item_name{
    return 'resellerpreference';
}

sub resource_name{
    return 'resellerpreferences';
}

sub container_resource_type{
    return 'resellers';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#resellers">Reseller</a>. The full list of properties can be obtained via <a href="/api/resellerpreferencedefs/">ResellerPreferenceDefs</a>.';
};

sub documentation_sample {
    return {
        cdr_export_field_separator => ",",
        cdr_export_sclidui_rwrs => "my cdr export rewrite rules",
    };
}

1;

# vim: set tabstop=4 expandtab:
