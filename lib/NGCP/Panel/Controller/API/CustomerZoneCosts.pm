package NGCP::Panel::Controller::API::CustomerZoneCosts;
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
            description => 'Filter for a specific start time in format YYYY-MM-DDThhmmss.',
        },
        {
            param => 'end',
            description => 'Filter for a specific end time in format YYYY-MM-DDThhmmss.',
        },
    ];
}


use parent qw/Catalyst::Controller NGCP::Panel::Role::API::CustomerZoneCosts/;

sub resource_name{
    return 'customerzonecosts';
}
sub dispatch_path{
    return '/api/customerzonecosts/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerzonecosts';
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
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $field_devs = $self->item_rs($c);

        (my $total_count, $field_devs) = $self->paginate_order_collection($c, $field_devs);
        my $query_string = $self->query_param_string($c);
        return unless $query_string;
        my (@embedded, @links);
        my $error_flag = 0;
        for my $dev ($field_devs->all) {
            my $hal = $self->hal_from_item($c, $dev);
            $error_flag = 1 unless $hal;
            push @embedded, $hal;
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d?%s', $self->dispatch_path, $dev->id, $query_string),
            );
        }
        last if $error_flag;
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s&%s', $self->dispatch_path, $page, $rows, $query_string));
        if(($total_count / $rows) > $page ) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'next',
                                              href => sprintf('%s?page=%d&rows=%d&%s', $self->dispatch_path, $page + 1, $rows, $query_string));
        }
        if($page > 1) {
            push @links, NGCP::Panel::Utils::DataHalLink->new(relation => 'prev',
                                              href => sprintf('%s?page=%d&rows=%d&%s', $self->dispatch_path, $page - 1, $rows, $query_string));
        }

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
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
