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
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'host',
            description => 'Filter for peering server host',
            query => {
                first => sub {
                    my $q = shift;
                    { host => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'ip',
            description => 'Filter for peering server ip',
            query => {
                first => sub {
                    my $q = shift;
                    { host => { like => $q } };
                },
                second => sub {},
            },
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
            name     => $resource->{name},
            group_id => $resource->{group_id},
        });
        if($dup_item) {
            $c->log->error("peering server with name '$$resource{name}' already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "peering server with this name already exists");
            return;
        }

        try {
            $item = $c->model('DB')->resultset('voip_peer_hosts')->create($resource);
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
            if($resource->{probe}) {
                NGCP::Panel::Utils::Peering::_sip_dispatcher_reload(c => $c);
            }
        } catch($e) {
            $c->log->error("failed to create peering server: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering server.");
            last;
        }

        $guard->commit;

        try {
            NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
            if($resource->{probe}) {
                NGCP::Panel::Utils::Peering::_sip_dispatcher_reload(c => $c);
            }
        } catch($e) {
            $c->log->error("failed to reload kamailio cache: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering server.");
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
