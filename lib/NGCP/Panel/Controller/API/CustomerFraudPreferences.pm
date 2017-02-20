package NGCP::Panel::Controller::API::CustomerFraudPreferences;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::CustomerFraudPreferences/;

sub resource_name{
    return 'customerfraudpreferences';
}
sub dispatch_path{
    return '/api/customerfraudpreferences/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerfraudpreferences';
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
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);

}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $customer_rs = $self->item_rs($c,0);
        (my $total_count, $customer_rs) = $self->paginate_order_collection($c, $customer_rs);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $customer ($customer_rs->all) {
            push @embedded, $self->hal_from_item($c, $customer, $form);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $customer->id),
            );
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

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
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

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

1;
