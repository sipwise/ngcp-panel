package NGCP::Panel::Controller::API::CallRecordingFiles;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallRecordingStreams/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/OPTIONS/];
}

#we don't have role package, so method will be here
sub resource_name{
    return 'callrecordingfiles';
}

sub api_description {
    return 'Defines the actual recording of a recorded call stream. It is referred to by the <a href="#callrecordingstreams">CallRecordingStreams</a> relation. A GET on an item returns the binary blob of the recording with the content type depending on the output format given in the related stream.';
};

1;

# vim: set tabstop=4 expandtab:
