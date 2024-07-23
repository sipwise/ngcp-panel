package NGCP::Panel::Controller::API::CallRecordingFiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/OPTIONS/];
}

sub api_description {
    return 'Defines the actual recording of a recorded call stream. It is referred to by the <a href="#callrecordingstreams">CallRecordingStreams</a> relation. A GET on an item returns the binary blob of the recording with the content type depending on the output format given in the related stream.';
};

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallRecordingStreams/;

sub resource_name{
    return 'callrecordingfiles';
}

sub dispatch_path{
    return '/api/callrecordingfiles/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callrecordingfiles';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    required_licenses => [qw/call_recording/],
});

1;

# vim: set tabstop=4 expandtab:
