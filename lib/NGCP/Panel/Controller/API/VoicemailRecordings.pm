package NGCP::Panel::Controller::API::VoicemailRecordings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::VoicemailRecordings/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/OPTIONS/];
}

sub resource_name{
    return 'voicemailrecordings';
}

sub api_description {
    return 'Defines the actual recording of voicemail messages. It is referred to by the <a href="#voicemails">Voicemails</a> relation. A GET on an item returns the binary blob of the recording with Content-Type "audio/x-wav".';
};

sub query_params {
    return [
        {
            param => 'format',
            description => 'Output format of the voicemail recording, supported: mp3, ogg, wav',
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
