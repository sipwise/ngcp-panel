package NGCP::Panel::Controller::API::EmergencyMappings;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DateTime;
use Path::Tiny qw(path);
use Safe::Isa qw($_isa);

use NGCP::Panel::Utils::EmergencyMapping;
use NGCP::Panel::Utils::MySQL;

require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}


sub api_description {
    return 'Defines emergency mappings for an <a href="#emergencymappingscontainer">Emergency Mapping Container</a>. You can POST mappings individually one-by-one using json. To bulk-upload mappings, specify the Content-Type as "text/csv", pass a reseller_id URL parameter and POST the CSV in the request body to the collection with an optional parameter "purge_existing=true", like "/api/emergencymappings/?reseller_id=123&purge_existing=true"';
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
            param => 'code',
            description => 'Filter for mappings with a specific code (wildcards possible)',
            query => {
                first => sub {
                    my $q = shift;
                    { code => { like => $q } };
                },
                second => sub {},
            },
        },
    ];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::EmergencyMappings/;

sub resource_name{
    return 'emergencymappings';
}
sub dispatch_path{
    return '/api/emergencymappings/';
}
sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-emergencymappings';
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
        } } @{ __PACKAGE__->allowed_methods }
    },
    action_roles => [qw(+NGCP::Panel::Role::HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
}

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
                        $c->log->error("Missing reseller_id");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "missing reseller_id parameter");
                        last;
                    }
                    unless($schema->resultset('resellers')->find($resource->{reseller_id})) {
                        $c->log->error("Invalid reseller_id '$$resource{reseller_id}'");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "invalid reseller_id '$$resource{reseller_id}'");
                        last;
                    }
                }
                if ($resource->{purge_existing} eq 'true') {
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
                $c->log->error("failed to upload csv: $e");
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Internal Server Error");
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
                $c->log->error("invalid emergency container id '$$resource{emergency_container_id}'");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "emergency container id does not exist");
                last;
            }
            if ($c->model('DB')->resultset('emergency_mappings')->search({
                    emergency_container_id => $container->id,
                    code => $resource->{code}
                },undef)->count > 0) {
                $c->log->error("Emergency mapping code '$$resource{code}' already defined for emergency container id '$$resource{emergency_container_id}'");
                $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "emergency mapping code already exists for emergency container");
                last;
            }

            my $item;
            try {
                $item = $c->model('DB')->resultset('emergency_mappings')->create($resource);
            } catch($e) {
                $c->log->error("failed to create emergency mapping: $e");
                $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create emergency mapping.");
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

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
