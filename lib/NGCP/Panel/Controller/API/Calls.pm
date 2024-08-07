package NGCP::Panel::Controller::API::Calls;
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
    return 'Defines calls placed or received by a customer.';
};

sub query_params {
    return [
        {
            param => 'customer_id',
            description => 'Filter for calls of a specific customer',
            query => {
                first => sub {
                    my $q = shift;
                    {
                        -or => [
                            { source_account_id => $q },
                            { destination_account_id => $q },
                        ],
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'subscriber_id',
            description => 'Filter for calls of a specific subscriber',
            new_rs => sub {
                my ($c,$q,$rs) = @_;
                my $subscriber = $c->model('DB')->resultset('voip_subscribers')->find($q);
                if ($subscriber) {
                    my $out_rs = $rs->search_rs({
                        source_user_id => $subscriber->uuid,
                    });
                    my $in_rs = $rs->search_rs({
                        destination_user_id => $subscriber->uuid,
                        source_user_id => { '!=' => $subscriber->uuid },
                    });
                    return $out_rs->union_all($in_rs);
                }
                return $rs;
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Calls/;

sub resource_name{
    return 'calls';
}

sub dispatch_path{
    return '/api/calls/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-calls';
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
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
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
