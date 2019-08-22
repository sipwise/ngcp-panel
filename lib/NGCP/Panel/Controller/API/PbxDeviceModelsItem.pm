package NGCP::Panel::Controller::API::PbxDeviceModelsItem;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::PbxDeviceModels/;

__PACKAGE__->set_config({
    PUT => {
        'ContentType' => ['multipart/form-data'],
        'Uploads'     => [qw/front_image mac_image front_thumbnail/],
    },
    allowed_roles => {
        'Default' => [qw/admin reseller subscriberadmin subscriber/],
        'PUT'     => [qw/admin reseller/],
        'PATCH'   => [qw/admin reseller/],
    }
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

1;

# vim: set tabstop=4 expandtab:
