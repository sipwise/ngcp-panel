package NGCP::Panel::Controller::API::CustomerZoneCosts;
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
    return 'Returns for each customer, the customer_id and the number of calls, the total duration and the call fees grouped by zone.';
};

sub query_params {
    return [
        {
            param => 'customer_id',
            description => 'Filter for a specific customer.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.id' => $q };
                },
                second => sub {
                    return {};
                },
            },
        },
        {
            param => 'start',
            description => 'Filter for a specific start time in format YYYY-MM-DDThhmmss',
        },
        {
            param => 'end',
            description => 'Filter for a specific end time in format YYYY-MM-DDThhmmss',
        },
        {
            param => 'direction',
            description => 'Filter for a specific call direction (in/out/in_out)',
        },
    ];
}


use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CustomerZoneCosts/;

sub resource_name{
    return 'customerzonecosts';
}

sub dispatch_path{
    return '/api/customerzonecosts/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerzonecosts';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $field_devs = $self->item_rs($c);

        (my $total_count, $field_devs, my $field_devs_rows) = $self->paginate_order_collection($c, $field_devs);
        my $query_string = $self->query_param_string($c);
        return unless $query_string;
        my (@embedded, @links);
        my $error_flag = 0;
        $self->expand_prepare_collection($c);
        for my $dev (@$field_devs_rows) {
            my $hal = $self->hal_from_item($c, $dev);
            $error_flag = 1 unless $hal;
            push @embedded, $hal;
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d?%s', $self->dispatch_path, $dev->id, $query_string),
            );
        }
        last if $error_flag;
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
