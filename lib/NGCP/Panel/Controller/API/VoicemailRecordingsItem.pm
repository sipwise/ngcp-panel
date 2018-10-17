package NGCP::Panel::Controller::API::VoicemailRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Subscriber;
use NGCP::Panel::Utils::Sounds;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::VoicemailRecordings/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub resource_name{
    return 'voicemailrecordings';
}

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, voicemailrecording => $item);
        my $format = $c->request->params->{format} // 'wav';
        unless ($format && $format =~ /^(wav|mp3|ogg)$/) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Unknown format '$format', supported: wav,mp3,ogg.");
            last;
        }
        my $sr = \%NGCP::Panel::Utils::Subscriber::;
        my $ss = \%NGCP::Panel::Utils::Sounds::;
        my $filename = $sr->{get_voicemail_filename}($c,$item,$format);
        $c->response->header ('Content-Disposition' => 'attachment; filename="'.$filename.'"');
        $c->response->content_type($sr->{get_voicemail_content_type}($c,$format));
        $c->response->body(${$ss->{transcode_data}(\$item->recording, 'WAV', uc($format))});
        return;
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
