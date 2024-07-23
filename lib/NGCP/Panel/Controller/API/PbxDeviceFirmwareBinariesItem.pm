package NGCP::Panel::Controller::API::PbxDeviceFirmwareBinariesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use NGCP::Panel::Utils::DeviceFirmware;
use NGCP::Panel::Utils::ValidateJSON qw();
require Catalyst::ActionRole::ACL;
require NGCP::Panel::Role::HTTPMethods;
require Catalyst::ActionRole::RequireSSL;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PbxDeviceFirmwares/;

sub resource_name{
    return 'pbxdevicefirmwarebinaries';
}

sub dispatch_path{
    return '/api/pbxdevicefirmwarebinaries/';
}

sub relation{
    return 'http://purl.org/sipwise/ngcp-api/#rel-pbxdevicefirmwarebinaries';
}

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller/],
    required_licenses => [qw/pbx device_provisioning/],
});

sub GET :Allow {
    my ($self, $c, $id) = @_;
    {
        last unless $self->valid_id($c, $id);
        my $item = $self->item_by_id($c, $id);
        last unless $self->resource_exists($c, pbxdevicefirmwarebinary => $item);
        my $resource = $self->resource_from_item($c, $item);

        $c->response->header ('Content-Disposition' => 'attachment; filename="' . $resource->{filename} . '"');
        $c->response->content_type('application/octet-stream');
        $c->response->body(
            NGCP::Panel::Utils::DeviceFirmware::get_firmware_data(
                c => $c, 
                fw_id => $item->id
            )
        );
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
