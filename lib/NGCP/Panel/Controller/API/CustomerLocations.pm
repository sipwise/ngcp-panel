package NGCP::Panel::Controller::API::CustomerLocations;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use NGCP::Panel::Utils::DataHal qw();
use NGCP::Panel::Utils::DataHalLink qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ContractLocations qw();
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

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
                             #distinct => 1 }; #not neccessary if _CHECK_BLOCK_OVERLAPS was always on
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

__PACKAGE__->config(
    action => {
        map { $_ => {
            ACLDetachTo => '/api/root/invalid_user',
            AllowedRole => [qw/admin reseller/],
            Args => 0,
            Does => [qw(ACL CheckTrailingSlash RequireSSL)],
            Method => $_,
            Path => __PACKAGE__->dispatch_path,
        } } @{ __PACKAGE__->allowed_methods },
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);



sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $cls = $self->item_rs($c);

        (my $total_count, $cls) = $self->paginate_order_collection($c, $cls);
        my (@embedded, @links);
        for my $cl ($cls->all) {
            push @embedded, $self->hal_from_item($c, $cl, $self->resource_name);
            push @links, NGCP::Panel::Utils::DataHalLink->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $cl->id),
            );
        }
        push @links,
            NGCP::Panel::Utils::DataHalLink->new(
                relation => 'curies',
                href => 'http://purl.org/sipwise/ngcp-api/#rel-{rel}',
                name => 'ngcp',
                templated => true,
            ),
            NGCP::Panel::Utils::DataHalLink->new(relation => 'profile', href => 'http://purl.org/sipwise/ngcp-api/');

        push @links, $self->collection_nav_links($page, $rows, $total_count, $c->request->path, $c->request->query_params);

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
            exceptions => ['contract_id'],
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

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
