package NGCP::Panel::Controller::API::MaliciousCalls;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
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

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::MaliciousCalls/;

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
            push @embedded, $self->hal_from_item($c, $item, $form);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('/%s%d', $c->request->path, $item->id),
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('/%s?page=%s&rows=%s', $c->request->path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('/%s?page=%d&rows=%d', $c->request->path, $page - 1, $rows));
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







1;

# vim: set tabstop=4 expandtab:
