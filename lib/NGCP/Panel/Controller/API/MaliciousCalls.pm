package NGCP::Panel::Controller::API::MaliciousCalls;
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
    return 'Defines a registered malicious calls list.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for malicious calls belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'reseller.id' => $q };
                },
                second => sub {
                    return { join => { 'subscriber' => {
                                       'contract' => {
                                       'contact' => 'reseller' } } } },
                },
            },
        },
        {
            param => 'callid',
            description => 'Filter by the call id',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'me.call_id' => $q,
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'caller',
            description => 'Filter by the caller number',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'me.caller' => $q,
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'callee',
            description => 'Filter by the callee number',
            query => {
                first => sub {
                    my $q = shift;
                    {
                       'me.callee' => $q,
                    };
                },
                second => sub {},
            },
        },
        {
            param => 'start_le',
            description => 'Filter by records with lower or equal than the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    $q .= ' 23:59:59' if($q =~ /^\d{4}\-\d{2}\-\d{2}$/);
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    { start_time => { '<=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
        {
            param => 'start_ge',
            description => 'Filter by records with greater or equal the specified time stamp.',
            query => {
                first => sub {
                    my $q = shift;
                    my $dt = NGCP::Panel::Utils::DateTime::from_string($q);
                    { 'me.start_time' => { '>=' => $dt->epoch } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::MaliciousCalls/;

sub resource_name{
    return 'maliciouscalls';
}
sub dispatch_path{
    return '/api/maliciouscalls/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-maliciouscalls';
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
);

sub gather_default_action_roles {
    my ($self, %args) = @_; my @roles = ();
    push @roles, 'NGCP::Panel::Role::HTTPMethods' if $args{attributes}->{Method};
    return @roles;
}

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
        (my $total_count, $items, my $items_rows) = $self->paginate_order_collection($c, $items);
        my (@embedded, @links);
        my $form = $self->get_form($c);
        for my $item (@$items_rows) {
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
            );
        }
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/'),
            $self->collection_nav_links($c, $page, $rows, $total_count, $c->request->path, $c->request->query_params);

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

# vim: set tabstop=4 expandtab:
