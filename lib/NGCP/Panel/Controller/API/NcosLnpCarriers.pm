package NGCP::Panel::Controller::API::NcosLnpCarriers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);


sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Allows to permit or reject calls to specific LNP carriers as part of an NCOS level.';
};

sub query_params {
    return [
        {
            param => 'ncos_level_id',
            description => 'Filter for NCOS LNP entries belonging to a specific NCOS level.',
            query => {
                first => sub {
                    my $q = shift;
                    { ncos_level_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'carrier_id',
            description => 'Filter for NCOS LNP entries belonging to a specific LNP carrier.',
            query => {
                first => sub {
                    my $q = shift;
                    { lnp_provider_id => $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::NcosLnpCarriers/;

sub resource_name{
    return 'ncoslnpcarriers';
}

sub dispatch_path{
    return '/api/ncoslnpcarriers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-ncoslnpcarriers';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
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

        my $form = $self->get_form($c);
        $resource->{lnp_provider_id} = delete $resource->{carrier_id};
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $level = $c->model('DB')->resultset('ncos_levels')->find(
            $resource->{ncos_level_id},
        );
        unless($level) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid ncos_level_id, level does not exist",
                         "invalid ncos_level_id '$$resource{ncos_level_id}'");
            return;
        }

        my $dup_item = $level->ncos_lnp_lists->search({
            lnp_provider_id => $resource->{lnp_provider_id},
        })->first;
        if($dup_item) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, 
                         "NCOS lnp entry already exists for given ncos level",
                         "ncos lnp entry with carrier '$$resource{lnp_provider_id}' already exists for ncos_level_id '$$resource{ncos_level_id}'");
            return;
        }

        my $item;
        try {
            $item = $level->ncos_lnp_lists->create($resource);
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create ncos lnp entry.", $e);
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
