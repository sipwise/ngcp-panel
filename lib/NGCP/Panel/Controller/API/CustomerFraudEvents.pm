package NGCP::Panel::Controller::API::CustomerFraudEvents;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a list of customers with fraud limits above defined thresholds for a specific interval.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for fraud events belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    return { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'interval',
            description => 'Interval filter. values: ["day", "month"].',
        },
        {
            param => 'notify_status',
            description => 'Notify status filter. values: ["new", "notified"].',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CustomerFraudEvents/;

sub resource_name{
    return 'customerfraudevents';
}

sub dispatch_path{
    return '/api/customerfraudevents/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerfraudevents';
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
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d-%s-%s', $c->request->path, $item->id, $item->interval, $item->interval_date),
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
