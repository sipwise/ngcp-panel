package NGCP::Panel::Controller::API::PbxDeviceConfigs;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use boolean qw(true);
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxDeviceConfigs/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub allowed_methods{
    return [qw/GET POST OPTIONS HEAD/];
}

sub api_description {
    return 'Defines configs for a <a href="#pbxdevicemodels">PbxDeviceModel</a>. To create or update a config, do a POST or PUT with the proper Content-Type (e.g. text/xml) and pass the properties via query parameters, e.g. <span>/api/pbxdeviceconfigs/?device_id=1&amp;version=1.0</span>';
};

sub query_params {
    return [
        {
            param => 'device_id',
            description => 'Filter for configs of a specific device model',
            query_type => 'string_eq',
        },
        {
            param => 'version',
            description => 'Filter for configs by a specific version',
            query_type => 'string_eq',
        },
        {
            param => 'content_type',
            description => 'Filter for configs by a specific content type',
            query_type => 'string_eq',
        },
    ];
}

sub POST :Allow {
    my ($self, $c) = @_;

    my $guard = $c->model('DB')->txn_scope_guard;
    {
        my $data = $self->get_valid_raw_post_data(
            c => $c, 
            media_type => [qw#text/plain text/xml#],
        );
        last unless $data;
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

        $resource->{data} = $data;
        $resource->{content_type} = $c->request->header('Content-Type');

        my $item;
        try {
            $item = $model->autoprov_configs->create($resource);
        } catch($e) {
            $c->log->error("failed to create pbxdeviceconfig: $e"); # TODO: user, message, trace, ...
            $self->error($c, HTTP_INTERNAL_SERVER_ERROR, "Failed to create pbxdeviceconfig.");
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
