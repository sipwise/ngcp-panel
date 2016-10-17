package NGCP::Panel::Controller::API::VoicemailRecordings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/OPTIONS/];
}

sub api_description {
    return 'Defines the actual recording of voicemail messages. It is referred to by the <a href="#voicemails">Voicemails</a> relation. A GET on an item returns the binary blob of the recording with Content-Type "audio/x-wav".';
};

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::VoicemailRecordings/;

sub resource_name{
    return 'voicemailrecordings';
}
sub dispatch_path{
    return '/api/voicemailrecordings/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-voicemailrecordings';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller subscriberadmin subscriber/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
);

sub query_params {
    return [
        {
            param => 'format',
            description => 'Output format of the voicemail recording, supported: mp3, ogg, wav',
        },
    ];
}

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}


1;

# vim: set tabstop=4 expandtab:
