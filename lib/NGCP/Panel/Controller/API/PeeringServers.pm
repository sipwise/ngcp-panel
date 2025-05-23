package NGCP::Panel::Controller::API::PeeringServers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Peering;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines peering servers.';
};

sub query_params {
    return [
        {
            param => 'group_id',
            description => 'Filter for peering server group',
            query => {
                first => sub {
                    my $q = shift;
                    { group_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'name',
            description => 'Filter for peering server name',
            query_type => 'wildcard',
        },
        {
            param => 'host',
            description => 'Filter for peering server host',
            query_type => 'wildcard',
        },
        {
            param => 'ip',
            description => 'Filter for peering server ip',
            query_type => 'wildcard',
        },
        {
            param => 'enabled',
            description => 'Filter for peering server enabled flag',
            query => {
                first => sub {
                    my $q = shift;
                    { enabled => $q };
                },
                second => sub {},
            },
        },    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PeeringServers/;

sub resource_name{
    return 'peeringservers';
}

sub dispatch_path{
    return '/api/peeringservers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-peeringservers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin/],
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

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c, 
            media_type => 'application/json',
        );
        last unless $resource;
        my $item;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        my $dup_item = $c->model('DB')->resultset('voip_peer_hosts')->find({
            name => $resource->{name},
        });
        if($dup_item) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering server with this name already exists",
                         "peering server with name '$$resource{name}' already exists");
            return;
        }

        try {
            $item = $c->model('DB')->resultset('voip_peer_hosts')->create($resource);
            if($resource->{probe}) {
                NGCP::Panel::Utils::Peering::sip_dispatcher_reload(c => $c);
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering server.", $e);
            last;
        }

        $guard->commit;

        NGCP::Panel::Utils::Peering::sip_lcr_reload(c => $c);

        try {
            if($resource->{probe}) {
                NGCP::Panel::Utils::Peering::sip_dispatcher_reload(c => $c);
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering server.",
                         "failed to reload kamailio cache", $e);
            last;
        }

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
