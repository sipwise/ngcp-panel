package NGCP::Panel::Controller::API::CallRecordingFiles;
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
    return 'Defines the actual recording of a recorded call stream. It is referred to by the <a href="#callrecordingstreams">CallRecordingStreams</a> relation. A GET on an item returns the binary blob of the recording with the content type depending on the output format given in the related stream.';
};

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::CallRecordingStreams/;

sub resource_name{
    return 'callrecordingfiles';
}
sub dispatch_path{
    return '/api/callrecordingfiles/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callrecordingfiles';
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

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}
1;

# vim: set tabstop=4 expandtab:
