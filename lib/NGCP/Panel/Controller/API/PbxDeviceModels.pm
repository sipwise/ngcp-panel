package NGCP::Panel::Controller::API::PbxDeviceModels;

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxDeviceModels/;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use boolean qw(true);
use HTTP::Status qw(:constants);
use Data::dumper;

use NGCP::Panel::Utils::DeviceBootstrap;
use NGCP::Panel::Utils::Device;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

# curl -v -X POST --user $USER --insecure -F front_image=@sandbox/spa504g-front.jpg -F mac_image=@sandbox/spa504g-back.jpg -F json='{"reseller_id":1, "vendor":"Cisco", "model":"SPA999", "linerange":[{"name": "Phone Keys", "can_private":true, "can_shared":true, "can_blf":true, "keys":[{"labelpos":"top", "x":5110, "y":5120},{"labelpos":"top", "x":5310, "y":5320}]}]}' https://localhost:4443/api/pbxdevicemodels/

sub api_description {
    return 'Specifies a model to be set in <a href="#pbxdeviceconfigs">PbxDeviceConfigs</a>. Use a Content-Type "multipart/form-data", provide front_image and mac_image parts with the actual images, and an additional json part with the properties specified below, e.g.: <code>curl -X POST --user $USER -F front_image=@/path/to/front.png -F mac_image=@/path/to/mac.png -F json=\'{"reseller_id":...}\' https://example.org:1443/api/pbxdevicemodels/</code> This resource is read-only to subscriberadmins.';
};

sub query_params {
    return [
        {
            param => 'reseller_id',
            description => 'Filter for models belonging to a certain reseller',
            query_type => 'string_eq',
        },
        {
            param => 'vendor',
            description => 'Filter for vendor matching a vendor name pattern',
            query_type => 'string_eq',
        },
        {
            param => 'model',
            description => 'Filter for models matching a model name pattern',
            query_type => 'string_like',
        },
    ];
}

sub documentation_sample {
    return  {
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
    } ;
}

sub POST :Allow {
    my ($self, $c) = @_;

    if ($c->user->roles eq 'subscriberadmin') {
        $c->log->error("role subscriberadmin cannot create pbxdevicemodels");
        $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Invalid role. Cannot create pbxdevicemodel.");
        return;
    }

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        last unless $self->forbid_link_header($c);
        last unless $self->valid_media_type($c, 'multipart/form-data');
        last unless $self->require_wellformed_json($c, 'application/json', $c->req->param('json'));
        my $resource = JSON::from_json($c->req->param('json'), { utf8 => 1 });
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

            my $linerange = delete $resource->{linerange};
            foreach my $range(@{ $linerange }) {

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

1;

# vim: set tabstop=4 expandtab:
