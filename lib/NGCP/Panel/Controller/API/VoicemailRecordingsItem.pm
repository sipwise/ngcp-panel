package NGCP::Panel::Controller::API::VoicemailRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();

use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Sounds;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::VoicemailRecordings/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    log_response => 0,
    GET => {
        #'application/json' is default, if no accept header was recieved.
        'ReturnContentType' => ['application/json', 'audio/x-wav', 'audio/mpeg', 'audio/ogg'],#,
    },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub resource_name{
    return 'voicemailrecordings';
}

sub get_item_binary_data{
    my($self, $c, $id, $item, $return_type) = @_;
    #caller waits for: $data_ref,$mime_type,$filename
    #while we will not strictly check Accepted header, if item can return only one type of the binary data
    my $format = mime_type_to_extension($return_type);
    my $data_ref;
    my $sr = \%NGCP::Panel::Utils::Subscriber::;
    my $ss = \%NGCP::Panel::Utils::Sounds::;
    if ($format ne 'wav') {
        $data_ref = $ss->{transcode_data}(\$item->recording, 'WAV', uc($format));
    } else {
        $data_ref = \$item->recording;
    }
    my $filename = $sr->{get_voicemail_filename}($c, $item, $format);
    return $data_ref, $return_type, $filename;
}

1;

# vim: set tabstop=4 expandtab:
