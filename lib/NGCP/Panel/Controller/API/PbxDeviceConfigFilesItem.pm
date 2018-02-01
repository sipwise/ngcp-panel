package NGCP::Panel::Controller::API::PbxDeviceConfigFilesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PbxDeviceConfigs/;

sub resource_name{
    return 'pbxdeviceconfigfiles';
}

sub dispatch_path{
    return '/api/pbxdeviceconfigfiles/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdeviceconfigfiles';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, pbxdevicefirmwarebinary => $item);
        my $resource = $self->resource_from_item($c, $item);

        $resource->{data} = $item->data;
        $c->response->header ('Content-Disposition' => 'attachment; filename="pbxdeviceconfig_' . $item->device_id . '_' . $item->id . '"');
        $c->response->content_type($item->content_type);
        $c->response->body($resource->{data});
        return;
    }
    return;
}

sub end : Private {
    my ($self, $c) = @_;

    #$self->log_response($c);
}

1;

# vim: set tabstop=4 expandtab:
