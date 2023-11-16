package NGCP::Panel::Controller::API::EmergencyMappingContainers;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::Reseller qw();

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines a container which holds a collection of <a href="#emergencymappings">Emergency Mappings</a>.';
};

sub query_params {
    return [
        {
            param => 'name',
            description => 'Filter for emergency mapping containers with a specific name',
            query_type => 'wildcard',
        },
        {
            param => 'reseller_id',
            description => 'Filter for emergency mapping containers for a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::EmergencyMappingContainers/;

sub resource_name{
    return 'emergencymappingcontainers';
}

sub dispatch_path{
    return '/api/emergencymappingcontainers/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-emergencymappingcontainers';
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
        if($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }
        my $dup_item = $c->model('DB')->resultset('emergency_containers')->find({
            reseller_id => $resource->{reseller_id},
            name => $resource->{name},
        });
        if($dup_item) {
            $c->log->error("emergency mapping container with name '$$resource{name}' already exists for this reseller");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "emergency mapping container with this name already exists for this reseller");
            return;
        }

        my $item;
        try {
            $item = $schema->resultset('emergency_containers')->create($resource);
        } catch($e) {
            $c->log->error("failed to create emergency mapping container: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create emergency mapping container.");
            last;
        }
        
        last unless $self->add_create_journal_item_hal($c,sub {
            my $self = shift;
            my ($c) = @_;
            my $_item = $self->item_by_id($c, $item->id);
            return $self->hal_from_item($c, $_item,$form); });

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('%s%d', $self->dispatch_path, $item->id));
        $c->response->body(q());
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
