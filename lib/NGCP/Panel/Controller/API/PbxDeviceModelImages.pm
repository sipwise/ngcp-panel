package NGCP::Panel::Controller::API::PbxDeviceModelImages;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::Entities NGCP::Panel::Role::API::PbxDeviceModelImages NGCP::Panel::Role::API::PbxDeviceModels/;

__PACKAGE__->set_config();

sub config_allowed_roles {
    return [qw/admin reseller subscriberadmin subscriber/];
}

sub allowed_methods{
    return [qw/OPTIONS/];
}

sub api_description {
    return 'Used to download the front and mac image of a <a href="#pbxdevicemodels">PbxDeviceModel</a>. Returns a binary attachment with the correct content type (e.g. image/jpeg) of the image.';
};

sub query_params {
    return [
        {
            param => 'type',
            description => 'Either "front" (default), "front_thumb" or "mac" to download one or the other.',
            query => {
                # handled directly in role
                first => sub {},
                second => sub {},
            }
        }
    ];
}

1;

# vim: set tabstop=4 expandtab:
