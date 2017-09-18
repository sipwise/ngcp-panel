package NGCP::Panel::Controller::API::PbxDeviceModelsItem;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PbxDeviceModels/;

__PACKAGE__->set_config();
sub _set_config{
    my ($self, $method) = @_;
    $method //='';
    if ('PUT' eq $method || 'PATCH' eq $method){
        return {
            'ContentType' => ['multipart/form-data'],#,
            'Uploads'     => [qw/front_image mac_image/],
#            Also correct way for the allowed_roles, and really the last word. Will be applied over all others.
#            'AllowedRole' => [qw/admin reseller/],
        };
    }
    return {};
}

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

1;

# vim: set tabstop=4 expandtab:
