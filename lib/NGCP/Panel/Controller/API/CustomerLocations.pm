package NGCP::Panel::Controller::API::CustomerLocations;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ContractLocations qw();

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'A Customer Location is a container for a number of network ranges.';
};

sub query_params {
    return [
        {
            param => 'ip',
            description => 'Filter for customer locations containing a specific IP address',
            query => {
                first => \&NGCP::Panel::Utils::ContractLocations::prepare_query_param_value,
                second => sub {
                    return { join => 'voip_contract_location_blocks',
                             group_by => 'me.id', }
                             #distinct => 1 }; #not necessary if _CHECK_BLOCK_OVERLAPS was always on
                },
            },
        },
        {
            param => 'name',
            description => 'Filter for customer locations matching a name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { name => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}


use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::CustomerLocations/;

sub resource_name{
    return 'customerlocations';
}

sub dispatch_path{
    return '/api/customerlocations/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-customerlocations';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $cls = $self->item_rs($c);

        (my $total_count, $cls, my $cls_rows) = $self->paginate_order_collection($c, $cls);
        my (@embedded, @links);
        for my $cl (@$cls_rows) {
            push @embedded, $self->hal_from_item($c, $cl, $self->resource_name);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $cl->id),
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
        my $schema = $c->model('DB');
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
        
        last unless $self->prepare_blocks_resource($c,$resource);
        my $blocks = delete $resource->{blocks};
        
        my $cl;
        try {
            $cl = $schema->resultset('voip_contract_locations')->create($resource);
            for my $block (@$blocks) {
                $cl->create_related('voip_contract_location_blocks', $block);
            }
        } catch($e) {
            $c->log->error("failed to create customer location: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create customer location.");
            return;
        };
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_cl = $self->item_by_id($c, $cl->id);
            return $self->hal_from_item($c, $_cl, $self->resource_name); });
        
        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $cl->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
