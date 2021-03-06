package NGCP::Panel::Controller::API::ProfilePreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub item_name{
    return 'profilepreference';
}

sub resource_name{
    return 'profilepreferences';
}

sub container_resource_type{
    return 'profiles';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#subscriberprofiles">Subscriber Profile</a>. The full list of properties can be obtained via <a href="/api/profilepreferencedefs/">ProfilePreferenceDefs</a>.';
};

1;

# vim: set tabstop=4 expandtab:
