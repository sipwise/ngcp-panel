package NGCP::Panel::Controller::API::CallRecordingStreams;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use DateTime::TimeZone;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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
                    { 'call' => $q };
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
        (my $total_count, $callrecordingstreams) = $self->paginate_order_collection($c, $callrecordingstreams);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $domain ($callrecordingstreams->all) {
            push @embedded, $self->hal_from_item($c, $domain, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $domain->id),
            );
        }
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
        }

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
