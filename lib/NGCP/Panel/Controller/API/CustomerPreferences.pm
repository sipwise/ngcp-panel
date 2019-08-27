package NGCP::Panel::Controller::API::CustomerPreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller ccareadmin ccare/],
});

sub item_name{
    return 'customerpreference';
}

sub resource_name{
    return 'customerpreferences';
}

sub container_resource_type{
    return 'contracts';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#customers">Customer</a>. The full list of properties can be obtained via <a href="/api/customerpreferencedefs/">CustomerPreferenceDefs</a>.';
};

sub query_params {
    return [
        {
            param => 'location_id',
            description => 'Fetch preferences for a specific location otherwise default preferences (location_id=null) are shown.',
        },
    ];
}

sub documentation_sample {
    return {
        block_in_mode  => JSON::true,
        block_in_list  => [ "1234" ],
        concurrent_max => 5,
    };
}

1;

# vim: set tabstop=4 expandtab:
