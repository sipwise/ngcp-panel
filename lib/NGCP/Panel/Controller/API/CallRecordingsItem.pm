package NGCP::Panel::Controller::API::CallRecordingsItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
use NGCP::Panel::Utils::Subscriber;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD DELETE/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::CallRecordings/;

sub resource_name{
    return 'callrecordings';
}

sub dispatch_path{
    return '/api/callrecordings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callrecordings';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, callrecording => $item);

        my $hal = $self->hal_from_item($c, $item);

        my $response = HTTP::Response->new(HTTP_OK, undef, HTTP::Headers->new(
            (map { # XXX Data::HAL must be able to generate links with multiple relations
                s|rel="(http://purl.org/sipwise/ngcp-api/#rel-\w+)"|rel="item $1"|r =~
                s/rel=self/rel="item self"/r;
            } $hal->http_headers),
        ), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

sub DELETE :Allow {
    my ($self, $c, $id) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, callrecording => $item);

        try {
            foreach my $stream($item->recording_streams->all) {
                unlink($stream->full_filename);
            }
            $item->recording_streams->delete;
            $item->recording_metakeys->delete;
            $item->delete;
        } catch($e) {
            $c->log->error("Failed to delete recording: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to delete recording.");
            last;
        }


        $item->delete;
        $guard->commit;

        $c->response->status(HTTP_NO_CONTENT);
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
