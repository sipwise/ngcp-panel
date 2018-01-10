package NGCP::Panel::Controller::API::Events;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Browse EDRs (event data records).';
};

sub query_params {
    return [
        {
            param => 'subscriber_id',
            description => 'Filter for events of a specific subscriber.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'subscriber_id' => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for events for customers/subscribers of a specific reseller.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'reseller.id' => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'type',
            description => 'Filter for events of a specific type.',
            query => {
                first => sub {
                    my $q = shift;
                    { type => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'timestamp_from',
            description => 'Filter for events occurred after or at the given time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'timestamp' => { '>=' => $dt->epoch  } };
                },
                second => sub {},
            },
        },
        {
            param => 'timestamp_to',
            description => 'Filter for events occurred before or at the given time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'timestamp' => { '<=' => $dt->epoch  } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::Events/;

sub resource_name{
    return 'events';
}
sub dispatch_path{
    return '/api/events/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-events';
}

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods }
    },
);


sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item ($items->all) {
            my $hal = $self->hal_from_item($c, $item, $form);
            $hal->_forcearray(1);
            push @embedded,$hal;
            my $link = NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
            $link->_forcearray(1);
            push @links, $link;
        }
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');

        push @links, $self->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

        my $hal = NGCP::Panel::Utils::DataHal->new(
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

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods_filtered($c);
    $c->response->headers(HTTP::Headers->new(
        Allow => join(', ', @{ $allowed_methods }),
        Accept_Post => 'application/hal+json; profile=http://purl.org/sipwise/ngcp-api/#rel-'.$self->resource_name,
    ));
    $c->response->content_type('application/json');
    $c->response->body(JSON::to_json({ methods => $allowed_methods })."\n");
    return;
}

1;
