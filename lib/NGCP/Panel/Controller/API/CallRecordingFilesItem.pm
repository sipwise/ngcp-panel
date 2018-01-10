package NGCP::Panel::Controller::API::CallRecordingFilesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use File::Slurp qw/read_file/;

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

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
            Args => 1,
            Does => [qw(ACL RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
);


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
            $c->log->error("Failed to read stream file: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to read stream file.");
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
