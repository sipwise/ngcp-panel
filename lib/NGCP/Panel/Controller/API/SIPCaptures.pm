package NGCP::Panel::Controller::API::SIPCaptures;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use DateTime::TimeZone;
use NGCP::Panel::Utils::DateTime;

sub allowed_methods{
    return [qw/GET OPTIONS/];
}

sub api_description {
    return 'Defines SIP packet captures for a call. A GET on item with call-id as the parameter returns pcap data as application/vnd.tcpdump.pcap.';
};

sub query_params {
    return [
		{
            param => 'call_id',
            description => 'Filter for a particular call_id',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'me.call_id' => $q,
                    };
                },
                second => sub {},
            },
		},
        {
            param => 'start_ge',
            description => 'Filter for data starting greater or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    { 'me.timestamp' => { '>=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
        {
            param => 'start_le',
            description => 'Filter for data starting lower or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    $q .= ' 23:59:59' if($q =~ /^\d{4}\-\d{2}\-\d{2}$/);
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    { 'me.timestamp' => { '<=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
		{
            param => 'method',
            description => 'Filter for a particular SIP method',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'me.method' => $q,
                    };
                },
                second => sub {},
            },
		},
		{
            param => 'subscriber_id',
            description => 'End time of the captured SIP data',
            query => {
                first => sub {
					my $q = shift;
                    {
						'voip_subscriber.id' => $q,
					};
                },
                second => sub {
					{
						join => 'voip_subscriber'
					};
				},
            },
		},
        {
            # we handle that separately/manually in the role
            param => 'tz',
            description => 'Format start_time according to the optional time zone provided here, e.g. Europe/Berlin.',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::SIPCaptures/;

sub resource_name{
    return 'sipcaptures';
}

sub dispatch_path{
    return '/api/sipcaptures/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-sipcaptures';
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

        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item ($items->all) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%s', $c->request->path, $item->call_id),
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
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = Data::HAL->new(
            embedded => [@embedded],
            links => [@links],
        );
        $hal->resource({
            total_count => $total_count,
        });
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
