package NGCP::Panel::Controller::API::PbxDeviceModels;
use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);
use MooseX::ClassAttribute qw(class_has);
use Data::Dumper;
use NGCP::Panel::Utils::DateTime;
use NGCP::Panel::Utils::DeviceBootstrap;
use NGCP::Panel::Utils::Device;
BEGIN { extends 'Catalyst::Controller::ActionRole'; }
require Catalyst::ActionRole::ACL;
require Catalyst::ActionRole::CheckTrailingSlash;
require Catalyst::ActionRole::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

# curl -v -X POST --user $USER --insecure -F front_image=@sandbox/spa504g-front.jpg -F mac_image=@sandbox/spa504g-back.jpg -F json='{"reseller_id":1, "vendor":"Cisco", "model":"SPA999", "linerange":[{"name": "Phone Keys", "can_private":true, "can_shared":true, "can_blf":true, "keys":[{"labelpos":"top", "x":5110, "y":5120},{"labelpos":"top", "x":5310, "y":5320}]}]}' https://localhost:4443/api/pbxdevicemodels/

class_has 'api_description' => (
    is => 'ro',
    isa => 'Str',
    default => 
        'Specifies a model to be set in <a href="#pbxdeviceconfigs">PbxDeviceConfigs</a>. Use a Content-Type "multipart/form-data", provide front_image and mac_image parts with the actual images, and an additional json part with the properties specified below, e.g.: <code>curl -X POST --user $USER -F front_image=@/path/to/front.png -F mac_image=@/path/to/mac.png -F json=\'{"reseller_id":...}\' https://example.org:1443/api/pbxdevicemodels/</code>',
);

class_has 'query_params' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[
        {
            param => 'reseller_id',
            description => 'Filter for models belonging to a certain reseller',
            query => {
                first => sub {
                    my $q = shift;
                    { reseller_id => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'vendor',
            description => 'Filter for vendor matching a vendor name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { vendor => $q };
                },
                second => sub {},
            },
        },
        {
            param => 'model',
            description => 'Filter for models matching a model name pattern',
            query => {
                first => sub {
                    my $q = shift;
                    { model => { like => $q } };
                },
                second => sub {},
            },
        },
    ]},
);

class_has 'documentation_sample' => (
    is => 'ro',
    default => sub { {
        vendor => "testvendor",
        model => "testmodel",
        reseller_id => 1,
        sync_method => "GET",
        sync_params => '[% server.uri %]/$MA',
        sync_uri => 'http://[% client.ip %]/admin/resync',
        linerange => [
            {
                name => "Phone Keys",
                can_private => 1,
                can_shared => 1,
                can_blf => 1,
                keys => [
                    {
                        x => 100,
                        y => 200,
                        labelpos => "left",
                    },
                    {
                        x => 100,
                        y => 300,
                        labelpos => "right",
                    },
                ],
            },
        ],
    } },
);


with 'NGCP::Panel::Role::API::PbxDeviceModels';

class_has('resource_name', is => 'ro', default => 'pbxdevicemodels');
class_has('dispatch_path', is => 'ro', default => '/api/pbxdevicemodels/');
class_has('relation', is => 'ro', default => 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicemodels');

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
    action_roles => [qw(HTTPMethods)],
);

sub auto :Private {
    my ($self, $c) = @_;

    $self->set_body($c);
    $self->log_request($c);
    return 1;
}

sub GET :Allow {
    my ($self, $c) = @_;
    my $page = $c->request->params->{page} // 1;
    my $rows = $c->request->params->{rows} // 10;
    {
        my $field_devs = $self->item_rs($c);

        (my $total_count, $field_devs) = $self->paginate_order_collection($c, $field_devs);
        my (@embedded, @links);
        for my $dev ($field_devs->all) {
            push @embedded, $self->hal_from_item($c, $dev);
            push @links, Data::HAL::Link->new(
                relation => 'ngcp:'.$self->resource_name,
                href     => sprintf('%s%d', $self->dispatch_path, $dev->id),
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
            Data::HAL::Link->new(relation => 'self', href => sprintf('%s?page=%s&rows=%s', $self->dispatch_path, $page, $rows));
        if(($total_count / $rows) > $page ) {
            push @links, Data::HAL::Link->new(relation => 'next', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page + 1, $rows));
        }
        if($page > 1) {
            push @links, Data::HAL::Link->new(relation => 'prev', href => sprintf('%s?page=%d&rows=%d', $self->dispatch_path, $page - 1, $rows));
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
        Allow => $allowed_methods->join(', '),
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
        last unless $self->forbid_link_header($c);
        last unless $self->valid_media_type($c, 'multipart/form-data');
        last unless $self->require_wellformed_json($c, 'application/json', $c->req->param('json'));
        my $resource = JSON::from_json($c->req->param('json'));
        $resource->{type} //= 'phone';
        $resource->{front_image} = $self->get_upload($c, 'front_image');
        last unless $resource->{front_image};
        # optional, don't set error
        $resource->{mac_image} = $c->req->upload('mac_image');

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $resource->{reseller_id} = $c->user->reseller_id;
        }

        my $reseller = $c->model('DB')->resultset('resellers')->find($resource->{reseller_id});
        unless($reseller) {
            $c->log->error("invalid reseller_id '$$resource{reseller_id}', does not exist");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid reseller_id, does not exist");
            last;
        }

        my $item;
        $item = $c->model('DB')->resultset('autoprov_devices')->find({
            reseller_id => $resource->{reseller_id},
            vendor => $resource->{vendor},
            model => $resource->{model},
        });
        if($item) {
            $c->log->error("device model with vendor '$$resource{vendor}' and model '$$resource{model}'already exists for reseller_id '$$resource{reseller_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Device model already exists for this reseller");
            last;
        }

        my $linerange = delete $resource->{linerange};
        unless(ref $linerange eq "ARRAY") {
            $c->log->error("linerange must be array");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid linerange parameter, must be array");
            last;
        }

        my $ft = File::Type->new();
        if($resource->{front_image}) {
            my $front_image = delete $resource->{front_image};
            $resource->{front_image} = $front_image->slurp;
            $resource->{front_image_type} = $ft->mime_type($resource->{front_image});
        }
        if($resource->{mac_image}) {
            my $front_image = delete $resource->{mac_image};
            $resource->{mac_image} = $front_image->slurp;
            $resource->{mac_image_type} = $ft->mime_type($resource->{mac_image});
        }

        try {
            my $connectable_models = delete $resource->{connectable_models};
            my $sync_parameters = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_prefetch($c, undef, $resource);
            my $credentials = NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_prefetch($c, undef, $resource);
            NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_clear($c, $resource);
            $item = $c->model('DB')->resultset('autoprov_devices')->create($resource);
            NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_credentials_store($c, $item, $credentials);
            NGCP::Panel::Utils::DeviceBootstrap::devmod_sync_parameters_store($c, $item, $sync_parameters);
            NGCP::Panel::Utils::DeviceBootstrap::dispatch_devmod($c, 'register_model', $item);
            NGCP::Panel::Utils::Device::process_connectable_models($c, 1, $item, $connectable_models );

            foreach my $range(@{ $linerange }) {
                unless(ref $range eq "HASH") {
                    $c->log->error("all elements in linerange must be hashes, but this is " . ref $range . ": " . Dumper $range);
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, all must be hash");
                    return;
                }
                foreach my $elem(qw/can_private can_shared can_blf keys/) {
                    unless(exists $range->{$elem}) {
                        $c->log->error("missing mandatory attribute '$elem' in a linerange element");
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, missing attribute '$elem'");
                        return;
                    }
                }
                unless(ref $range->{keys} eq "ARRAY") {
                    $c->log->error("linerange.keys must be array");
                    $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid linerange.keys parameter, must be array");
                    last;
                }
                $range->{num_lines} = @{ $range->{keys} }; # backward compatibility
                my $keys = delete $range->{keys};

                my $r = $item->autoprov_device_line_ranges->create($range);
                my $i = 0;
                foreach my $label(@{ $keys }) {
                    $label->{line_index} = $i++;
                    unless(ref $label eq "HASH") {
                        $c->log->error("all elements in linerange must be hashes, but this is " . ref $range . ": " . Dumper $range);
                        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid range definition inside linerange parameter, all must be hash");
                        return;
                    }
                    $label->{position} = delete $label->{labelpos};
                    $r->annotations->create($label);
                }
            }
        } catch($e) {
            $c->log->error("failed to create device model: $e");
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create device model.");
            last;
        }

        $guard->commit;

        $c->response->status(HTTP_CREATED);
        $c->response->header(Location => sprintf('/%s%d', $c->request->path, $item->id));
        $c->response->body(q());
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    $self->log_response($c);
    return 1;
}

# vim: set tabstop=4 expandtab:
