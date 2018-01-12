package NGCP::Panel::Controller::API::PbxDevicePreferenceDefs;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Preferences;
use JSON::Types qw();
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntityPreferenceDefs NGCP::Panel::Role::API/;

sub resource_name{
    return 'pbxdevicepreferencedefs';
}

sub dispatch_path{
    return '/api/pbxdevicepreferencedefs/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicepreferencedefs';
}

__PACKAGE__->set_config();

sub config_allowed_roles {
    return [qw/admin reseller/];
}

1;

# vim: set tabstop=4 expandtab:
