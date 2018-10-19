package NGCP::Panel::Controller::API::VoicemailRecordings;
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

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub query_params {
    return [
        {
            param       => 'format',
            description => 'Output format of the voicemail recording, supported: mp3, ogg, wav',
            type        => 'mime_type',   
        },
    ];
}

1;

# vim: set tabstop=4 expandtab:
