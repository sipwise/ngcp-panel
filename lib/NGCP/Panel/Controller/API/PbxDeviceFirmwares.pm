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
            $c->log->error("invalid device_id '$$resource{device_id}'");
            $self->error($c, HTTP_UNPROCESSABLE_ENTITY, "Pbx device model does not exist");
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
            $c->log->error("failed to create pbxdevicefirmware: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create pbxdevicefirmware.");
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
