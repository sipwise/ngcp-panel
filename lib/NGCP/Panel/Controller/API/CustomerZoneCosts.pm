package NGCP::Panel::Controller::API::CustomerZoneCosts;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use NGCP::Panel::Utils::DateTime;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Returns for each customer, the customer_id and the number of calls, the total duration and the call fees grouped by zone.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
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
    ]},
);


with 'NGCP::Panel::Role::API::CustomerZoneCosts';

class_has('resource_name', is => 'ro', default => 'customerzonecosts');
class_has('dispatch_path', is => 'ro', default => '/api/customerzonecosts/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-customerzonecosts');

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
    action_roles => [qw(HTTPMethods)],
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

        my $total_count = int($field_devs->count);
        $field_devs = $field_devs->search(undef, {
            page => $page,
            rows => $rows,
        });
        my $query_string = $self->query_param_string($c);
        return unless $query_string;
        my (@embedded, @links);
        my $error_flag = 0;
        for my $dev ($field_devs->search({}, {order_by => {-asc => 'me.id'}})->all) {
            my $hal = $self->hal_from_item($c, $dev);
            $error_flag = 1 unless $hal;
            push @embedded, $hal;
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d?%s', $self->dispatch_path, $dev->id, $query_string),
            );
        }
        last if $error_flag;
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            Data::HAL::Link->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s&%s', $self->dispatch_path, $page, $rows, $query_string));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next',
                                              href => sprintf('%s?page=%d&rows=%d&%s', $self->dispatch_path, $page + 1, $rows, $query_string));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev',
                                              href => sprintf('%s?page=%d&rows=%d&%s', $self->dispatch_path, $page - 1, $rows, $query_string));
        }

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

sub HEAD :Allow {
    my ($self, $c) = @_;
    $c->forward(qw(GET));
    $c->response->body(q());
    return;
}

sub OPTIONS :Allow {
    my ($self, $c) = @_;
    my $allowed_methods = $self->allowed_methods;
    $c->response->headers(HTTP::Headers->new(
        Allow => $allowed_methods->join(', '),
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

# vim: set tabstop=4 expandtab:
