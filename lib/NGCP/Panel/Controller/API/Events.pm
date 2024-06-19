package NGCP::Panel::Controller::API::Events;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;

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
            query_type => 'wildcard',
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

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Events/;

sub resource_name{
    return 'events';
}

sub dispatch_path{
    return '/api/events/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-events';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $items = $self->item_rs($c);
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        $self->expand_prepare_collection($c);
        for my $item (@$items_rows) {
            my $hal = $self->hal_from_item($c, $item, $form);
            $hal->_forcearray(1);
            push @embedded,$hal;
            my $link = Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
            $link->_forcearray(1);
            push @links, $link;
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
        my $response = HTTP::Response->new(HTTP_OK, undef,
            HTTP::Headers->new($hal->http_headers(skip_links => 1)), $hal->as_json);
        $c->response->headers($response->headers);
        $c->response->body($response->content);
        return;
    }
    return;
}

1;
