package NGCP::Panel::Controller::API::CallRecordingFilesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Status qw(:constants);
use File::Slurp qw/read_file/;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallRecordingStreams/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    log_response => 0,
    GET => {
        ReturnContentType => 'binary',
    },
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub resource_name{
    return 'callrecordingfiles';
}

sub get_item_binary_data{
    my($self, $c, $id, $item) = @_;
    my $data;
    my $mime_type;
    my $filename;
    if($item->file_format eq "wav") {
        $mime_type = 'audio/x-wav';
    } elsif($item->file_format eq "mp3") {
        $mime_type = 'audio/mpeg';
    } else {
        $mime_type = 'application/octet-stream';
    }
    try {
        $data = read_file($item->full_filename);
    } catch($e) {
        $c->log->error("Failed to read stream file: $e");
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to read stream file.");
        last;
    }
    $filename = $self->resource_name . '-' . $item->id . '.' . lc($item->file_format);

    return (\$data, $mime_type, $filename);
}

1;

# vim: set tabstop=4 expandtab:
