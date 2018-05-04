package NGCP::Panel::Controller::API::PeeringServerPreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub item_name{
    return 'peeringserverpreference';
}

sub resource_name{
    return 'peeringserverpreferences';
}

sub container_resource_type{
    return 'peerings';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#peeringservers">Peering servers</a>. The full list of properties can be obtained via <a href="/api/peeringserverpreferencedefs/">PeeringSserverPreferenceDefs</a>.';
};

sub documentation_sample {
    return {
        force_outbound_calls_to_peer => "never",
        transport_protocol => "transparent",
        use_rtpproxy => "ice_strip_candidates",
    };
}

1;

# vim: set tabstop=4 expandtab:
