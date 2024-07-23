package NGCP::Panel::Controller::API::CallRecordingStreams;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use DateTime::TimeZone;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines recording streams of a call recorded in <a href="#callrecordings">CallRecordings</a>. The file content can be fetched via in <a href="#callrecordingfiles">CallRecordingFiles</a>.';
};

sub query_params {
    return [
        {
            param => 'recording_id',
            description => 'Filter for callrecording streams belonging to a specific recording session.',
            query => {
                first => sub {
                    my $q = shift;
                    { 'me.call' => $q };
                },
                second => sub {}
            },
        },
        {
            param => 'type',
            description => 'Filter for callrecording streams with a specific type ("single" or "mixed")',
            query => {
                first => sub {
                    my $q = shift;
                    { 'output_type' => $q };
                },
                second => sub {},
            },
        },
        {
            # we handle that separately/manually in the role
            param => 'tz',
            description => 'Format start_time according to the optional time zone provided here, e.g. Europe/Berlin.',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CallRecordingStreams/;

sub resource_name{
    return 'callrecordingstreams';
}

sub dispatch_path{
    return '/api/callrecordingstreams/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-callrecordingstreams';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
    required_licenses => [qw/call_recording/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        if($c->req->param('tz') && !DateTime::TimeZone->is_valid_name($c->req->param('tz'))) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Query parameter 'tz' value is not a valid time zone");
            return;
        }
        my $callrecordingstreams = $self->item_rs($c);
        (my $total_count, $callrecordingstreams, my $callrecordingstreams_rows) = $self->paginate_order_collection($c, $callrecordingstreams);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        $self->expand_prepare_collection($c);
        for my $domain (@$callrecordingstreams_rows) {
            push @embedded, $self->hal_from_item($c, $domain, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $domain->id),
            );
        }
        $self->expand_collection_fields($c, \@embedded);
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
        my $rname = $self->resource_name;

        my $response = HTTP::Response->new(HTTP_OK, undef, 
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
