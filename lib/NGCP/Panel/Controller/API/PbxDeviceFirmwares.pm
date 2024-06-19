package NGCP::Panel::Controller::API::PbxDeviceFirmwares;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DeviceFirmware;

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines firmwares for a <a href="#pbxdevicemodels">PbxDeviceModel</a>. To create or update a firmware, do a POST or PUT with Content-Type application/octet-stream and pass the properties via query parameters, e.g. <span>/api/pbxdevicefirmwares/?device_id=1&amp;filename=test.bin&amp;version=1.0</span>';
};

sub query_params {
    return [
        {
            param => 'device_id',
            description => 'Filter for firmwares of a specific device model',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'device_id' => $q };
                },
                second => sub { },
            },
        },
		{
            param => 'version',
            description => 'Filter for firmwares by a specific version',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'version' => $q };
                },
                second => sub { },
            },
		},
		{
            param => 'filename',
            description => 'Filter for firmwares by a specific file name',
            query => {
                first => sub {
                    my $q = shift;
                    return { 'filename' => $q };
                },
                second => sub { },
            },
        },
    ];
}

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxDeviceFirmwares/;

sub resource_name{
    return 'pbxdevicefirmwares';
}

sub dispatch_path{
    return '/api/pbxdevicefirmwares/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicefirmwares';
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
        my $binary = $self->get_valid_raw_post_data(
            c => $c, 
            media_type => 'application/octet-stream',
        );
        last unless $binary;
        my $resource = $c->req->query_params;

        my $form = $self->get_form($c);
        last unless $self->validate_form(
            c => $c,
            resource => $resource,
            form => $form,
        );

        my $model_rs = $c->model('DB')->resultset('autoprov_devices')->search({ 
            id => $resource->{device_id} 
        });
        if($c->user->roles eq "admin") {
        } elsif($c->user->roles eq "reseller") {
            $model_rs = $model_rs->search({
                reseller_id => $c->user->reseller_id,
            });
        }
        my $model = $model_rs->first;
        unless($model) {
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device model does not exist",
                         "invalid device_id '$$resource{device_id}'");
            last;
        }

        last unless($resource);

        my $item;
        try {
            $item = $model->autoprov_firmwares->create($resource);
            if ($binary) {
                NGCP::Panel::Utils::DeviceFirmware::insert_firmware_data(
                    c => $c, fw_id => $item->id, data_ref => \$binary
                );
            }
        } catch($e) {
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create pbxdevicefirmware.", $e);
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
