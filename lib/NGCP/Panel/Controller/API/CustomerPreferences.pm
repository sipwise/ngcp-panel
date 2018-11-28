package NGCP::Panel::Controller::API::CustomerPreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use JSON qw();

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

sub container_resource_type{
    return 'contracts';
}

sub api_description {
    return 'Specifies certain properties (preferences) for a <a href="#customers">Customer</a>. The full list of properties can be obtained via <a href="/api/customerpreferencedefs/">CustomerPreferenceDefs</a>.';
};

sub query_params {
    return [
        {
            param => 'location_id',
            description => 'Fetch preferences for a specific location otherwise default preferences (location_id=null) are shown.',
        },
    ];
}

sub documentation_sample {
    return {
        block_in_mode  => JSON::true,
        block_in_list  => [ "1234" ],
        concurrent_max => 5,
    };
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::Preferences/;

sub resource_name{
    return 'customerpreferences';
}

sub dispatch_path{
    return '/api/customerpreferences/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerpreferences';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $customers = $self->item_rs($c, "contracts");
        (my $total_count, $customers) = $self->paginate_order_collection($c, $customers);
        my (@embedded, @links);
        for my $customer ($customers->all) {
            push @embedded, $self->hal_from_item($c, $customer, "contracts");
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $customer->id),
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
