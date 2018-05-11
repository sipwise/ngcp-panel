package NGCP::Panel::Controller::API::DomainPreferences;
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
    return 'domainpreference';
}

sub resource_name{
    return 'domainpreferences';
}

sub container_resource_type{
    return 'domains';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#domains">Domain</a>. The full list of properties can be obtained via <a href="/api/domainpreferencedefs/">DomainPreferenceDefs</a>.';
};

sub documentation_sample {
    return {
        outbound_from_user => "upn",
        outbound_to_user => "callee",
        concurrent_max => 5,
        use_rtpproxy => "ice_strip_candidates",
    };
}

1;

# vim: set tabstop=4 expandtab:
