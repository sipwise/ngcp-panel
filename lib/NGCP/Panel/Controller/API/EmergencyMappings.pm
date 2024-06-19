package NGCP::Panel::Controller::API::EmergencyMappings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;

use NGCP::Panel::Utils::EmergencyMapping;
use NGCP::Panel::Utils::MySQL;


sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines emergency mappings for an <a href="#emergencymappingscontainer">Emergency Mapping Container</a>. You can POST mappings individually one-by-one using json. To bulk-upload mappings, specify the Content-Type as "text/csv", pass a reseller_id URL parameter and POST the CSV in the request body to the collection with an optional parameter "purge_existing=true", like "/api/emergencymappings/?reseller_id=123&amp;purge_existing=true"';
};

sub query_params {
    return [
        {
            param => 'emergency_container_id',
            description => 'Filter for emergency mappings belonging to a specific emergency mapping container',
            query => {
                first => sub {
                    my $q = shift;
                    { emergency_container_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'reseller_id',
            description => 'Filter for emergency mappings belonging to a specific reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { 'emergency_container.reseller_id' => $q };
                },
                second => sub {
                    return { join => 'emergency_container' };
                },
            },
        },
        {
            param => 'code',
            description => 'Filter for mappings with a specific code',
            query_type => 'wildcard',
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::EmergencyMappings/;

sub resource_name{
    return 'emergencymappings';
}

sub dispatch_path{
    return '/api/emergencymappings/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-emergencymappings';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub check_create_csv :Private {
    my ($self, $c) = @_;
    my $reseller_id = $c->request->params->{reseller_id};
    if (!$reseller_id) {
        $self->error($c, HTTP_BAD_REQUEST, 'reseller_id  parameter is necessary to download csv data.');
        return;
    }
    return 'emergency_mapping_list_reseller_'.$reseller_id.'.csv';
}

sub create_csv :Private {
    my ($self, $c) = @_;
    NGCP::Panel::Utils::EmergencyMapping::create_csv(
        c => $c,
        reseller_id => $c->request->params->{reseller_id},
    );
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $header_accept = $c->request->header('Accept');
    if(defined $header_accept && $header_accept eq 'text/csv') {
        $self->return_csv($c);
        return;
    }
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
        my $schema = $c->model('DB');
        my $resource;
        my $data = $self->get_valid_raw_post_data(
            c => $c,
            media_type => [qw#application/json text/csv#],
        );
        last unless $data;

        if($c->request->header('Content-Type') eq 'text/csv') {
            $resource = $c->req->query_params;
        } else {
            last unless $self->require_wellformed_json($c, 'application/json', $data);
            $resource = JSON::from_json($data, { utf8 => 1 });
            $data = undef;
        }

        if ($data) {
            my($mappings, $fails, $text_success);
            try {
                if($c->user->roles eq "reseller") {
                    $resource->{reseller_id} = $c->user->reseller_id;
                } else {
                    unless(defined $resource->{reseller_id}) {
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "missing reseller_id parameter");
                        last;
                    }
                    unless($schema->resultset('resellers')->find($resource->{reseller_id})) {
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "invalid reseller_id '$$resource{reseller_id}'");
                        last;
                    }
                }
                if ($resource->{purge_existing} && $resource->{purge_existing} eq 'true')  {
                    my ($start, $end);
                    $start = time;
                    my $rs = $schema->resultset('emergency_containers')->search({
                        reseller_id => $resource->{reseller_id},
                    });
                    $rs->delete;
                    $end = time;
                    $c->log->debug("API Purging emergency mappings entries took " . ($end - $start) . "s");
                }

                ( $mappings, $fails, $text_success ) = NGCP::Panel::Utils::EmergencyMapping::upload_csv(
                    c       => $c,
                    data    => \$data,
                    schema  => $schema,
                    reseller_id => $resource->{reseller_id},
                );

                $c->log->info( $$text_success );

                $guard->commit;

                $c->response->status(HTTP_CREATED);
                $c->response->body(q());

            } catch($e) {
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error",
                             "failed to upload csv", $e);
                last;
            };
        } else {
            delete $resource->{purge_existing};

            my $form = $self->get_form($c);
            last unless $self->validate_form(
                c => $c,
                resource => $resource,
                form => $form,
            );

            my $container = $c->model('DB')->resultset('emergency_containers')->find($resource->{emergency_container_id});
            unless($container) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "emergency container id does not exist",
                             "invalid emergency container id '$$resource{emergency_container_id}'");
                last;
            }
            if ($c->model('DB')->resultset('emergency_mappings')->search({
                    emergency_container_id => $container->id,
                    code => $resource->{code}
                },undef)->count > 0) {
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY,
                             "Emergency mapping code already exists for emergency container",
                             "Emergency mapping code '$$resource{code}' already defined for emergency container id '$$resource{emergency_container_id}'");
                last;
            }

            my $item;
            try {
                $item = $c->model('DB')->resultset('emergency_mappings')->create($resource);
            } catch($e) {
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create emergency mapping.", $e);
                last;
            }

            $guard->commit;

            $c->response->status(HTTP_CREATED);
            $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
            $c->response->body(q());
        }
    }
    return;
}

1;

# vim: set tabstop=4 expandtab:
