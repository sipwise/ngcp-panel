package NGCP::Panel::Controller::API::CustomerFraudPreferences;
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
    return 'Defines fraud preferences per customer contract.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for fraud preferences of contracts belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'contact.reseller_id' => $q };
                },
                second => undef,
            },
        },
        {
            param => 'contact_id',
            description => 'Filter for fraud preferences of contracts with a specific contact id',
            query => {
                first => sub {
                    my $q = shift;
                    { contact_id => $q };
                },
                second => undef,
            },
        },
        {
            param => 'notify',
            description => 'Filter for fraud preferences of contracts containing a specific notification email address',
            query => {
                first => sub {
                    my $q = shift;
                    { '-or' => [
                        fraud_interval_notify => { like => '%'.$q.'%' },
                        fraud_daily_notify => { like => '%'.$q.'%' }
                    ]};
                },
                second => sub {
                    { join => 'contract_fraud_preference' };
                },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CustomerFraudPreferences/;

sub resource_name{
    return 'customerfraudpreferences';
}

sub dispatch_path{
    return '/api/customerfraudpreferences/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerfraudpreferences';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $customer_rs = $self->item_rs($c,0);
        (my $total_count, $customer_rs, my $customer_rows) = $self->paginate_order_collection($c, $customer_rs);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        $self->expand_prepare_collection($c);
        for my $customer (@$customer_rows) {
            push @embedded, $self->hal_from_item($c, $customer, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $customer->id),
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
