package NGCP::Panel::Controller::API::TopupLogs;
use Sipwise::Base;
use namespace::sweep;
use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
#use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default =>
        'Log of successful and failed <a href="#topupcash">TopupCash</a> and <a href="#topupvoucher">TopupVoucher</a> requests.',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'reseller_id',
            description => 'Filter for top-up requests for customers/subscribers of a specific reseller.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'contact.reseller.id' => $q };
                },
                second => sub {
                    return {
                        join => { 'contract' => 'contact' }
                    },
                },
            },
        },
        {
            param => 'request_token',
            description => 'Filter for top-up requests with the given request_token.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.request_token' => $q };
                },
                second => sub { },
            },
        },
        {
            param => 'timestamp_from',
            description => 'Filter for top-up requests performed after or at the given time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'me.timestamp' => { '>=' => $dt->epoch  } };
                },
                second => sub { },
            },
        },
        {
            param => 'timestamp_to',
            description => 'Filter for top-up requests performed before or at the given time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    return { 'me.timestamp' => { '<=' => $dt->epoch  } };
                },
                second => sub { },
            },
        },        
        {
            param => 'contract_id',
            description => 'Filter for top-up requests of a specific customer contract.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.contract_id' => $q };
                },
                second => sub {},
            },
        },
       {
            param => 'subscriber_id',
            description => 'Filter for top-up requests of a specific subscriber.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.subscriber_id' => $q };
                },
                second => sub {},
            },
        },
       {
            param => 'voucher_id',
            description => 'Filter for top-up requests with a specific voucher.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.voucher_id' => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'outcome',
            description => 'Filter for top-up requests by outcome.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.outcome' => $q };
                },
                second => sub { },
            },
        },
        {
            param => 'amount_above',
            description => 'Filter for top-up requests with an amount greater than or equal to the given value in USD/EUR/etc.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.amount' => { '>=' => $q * 100.0  } };
                },
                second => sub { },
            },
        },
        {
            param => 'amount_below',
            description => 'Filter for top-up requests with an amount less than or equal to the given value in USD/EUR/etc.',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'me.amount' => { '<=' => $q * 100.0  } };
                },
                second => sub { },
            },
        },         
    ]},
);

with 'NGCP::Panel::Role::API::TopupLogs';

class_has('resource_name', is => 'ro', default => 'topuplogs');
class_has('dispatch_path', is => 'ro', default => '/api/topuplogs/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-topuplogs');

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
    action_roles => [qw(HTTPMethods)],
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
        my $items = $self->item_rs($c);
        (my $total_count, $items) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item ($items->all) {
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
        push @links,
            Data::HAL::Link->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            Data::HAL::Link->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');
       
        push @links, $self->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

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
    my $allowed_methods = $self->allowed_methods_filtered($c);
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
}
