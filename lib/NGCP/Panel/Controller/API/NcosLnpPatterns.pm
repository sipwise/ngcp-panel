package NGCP::Panel::Controller::API::NcosLnpPatterns;
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
    return 'NCOS Lnp Patterns define rules within Lnp Lists.';
};

sub query_params {
    return [
        {
            param => 'ncos_lnp_list_id',
            description => 'Filter for Lnp patterns belonging to a specific NCOS Lnp List.',
            query => {
                first => sub {
                    my $q = shift;
                    { ncos_lnp_list_id => $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::NcosLnpPatterns/;

sub resource_name{
    return 'ncoslnppatterns';
}

sub dispatch_path{
    return '/api/ncoslnppatterns/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-ncoslnppatterns';
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

        my $lnp_list_rs = $c->model('DB')->resultset('ncos_lnp_list')->search({
            id => $resource->{ncos_lnp_list_id},
        });
        my $lnp_list = $lnp_list_rs->first;
        unless($lnp_list) {
            $c->log->error("invalid ncos_lnp_list_id '$$resource{ncos_lnp_list_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid ncos_lnp_list_id, lnp list does not exist");
            return;
        }

        my $dup_item = $lnp_list->ncos_lnp_pattern_lists->search({
            pattern => $resource->{pattern},
        })->first;
        if($dup_item) {
            $c->log->error("ncos pattern '$$resource{pattern}' already exists for ncos_lnp_list_id '$$resource{ncos_lnp_list_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "NCOS pattern already exists for given ncos lnp list id");
            return;
        }

        my $item;
        try {
            $item = $lnp_list->ncos_lnp_pattern_lists->create($resource);
        } catch($e) {
            $c->log->error("failed to create ncos lnp pattern: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create ncos lnp pattern.");
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
