package NGCP::Panel::Controller::API::PeeringGroups;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
#
use NGCP::Panel::Utils::Peering;
use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PeeringGroups/;#Catalyst::Controller

__PACKAGE__->set_config({
    own_transaction_control => { POST => 1 },
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines peering groups.';
};

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for peering group name',
            query_type => 'wildcard',
        },
        {
            param => 'description',
            description => 'Filter for peering group description',
            query_type => 'wildcard',
        },
    ];
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
        for my $item (@$items_rows) {
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

sub create_item {
    my ($self, $c, $resource, $form, $process_extras) = @_;

    my $item;
    my $guard = $c->model('DB')->txn_scope_guard;
    try {
        my $dup_item = $c->model('DB')->resultset('voip_peer_groups')->find({
            name => $resource->{name},
        });

        if ($dup_item) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Peering group with this name already exists",
                         "peering group with name '$$resource{name}' already exists");
            return;
        }

        $item = $c->model('DB')->resultset('voip_peer_groups')->create($resource);

        $guard->commit;

    } catch($e) {
        $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering group.", $e);
        return;
    }
    NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
    return $item;
}

1;

# vim: set tabstop=4 expandtab:
