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
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
        {
            param => 'description',
            description => 'Filter for peering group description',
            query => {
                first => sub {
                    my $q = shift;
                    { description => { like => $q } };
                },
                second => sub {},
            },
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

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $resource = $self->get_valid_post_data(
            c => $c,
            media_type => 'application/json',
        );
        last unless $resource;

        my $form = $self->get_form($c);

        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );
        last unless $resource;

        $resource = $self->process_form_resource($c, undef, undef, $resource, $form);

        my $item;
        my $dup_item = $c->model('DB')->resultset('voip_peer_groups')->find({
            name => $resource->{name},
        });
        if($dup_item) {
            $c->log->error("peering group with name '$$resource{name}' already exists"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Peering group with this name already exists");
            last;
        }

        try {
            $item = $c->model('DB')->resultset('voip_peer_groups')->create($resource);
        } catch($e){
            $c->log->error("failed to create peering group: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create peering group.");
            last;
        }

        $guard->commit;

        NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
