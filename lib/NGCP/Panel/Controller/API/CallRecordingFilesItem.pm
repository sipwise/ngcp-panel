package NGCP::Panel::Controller::API::CallRecordingFilesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use File::Slurp qw/read_file/;


sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallRecordingStreams/;

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
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, callrecordingfile => $item);

        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $self->resource_name . '-' . $item->id . '.' . lc($item->file_format));

        my $data;
        try {
            $data = read_file($item->full_filename);
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to read stream file.", $e);
            last;
        }
        my $mime_type;
        if($item->file_format eq "wav") {
            $mime_type = 'audio/x-wav';
        } elsif($item->file_format eq "mp3") {
            $mime_type = 'audio/mpeg';
        } else {
            $mime_type = 'application/octet-stream';
        }

        $c->response->content_type($mime_type);
        $c->response->body($data);
        return;
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;
}

1;

# vim: set tabstop=4 expandtab:
