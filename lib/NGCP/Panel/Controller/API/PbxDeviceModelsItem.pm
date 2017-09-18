package NGCP::Panel::Controller::API::PbxDeviceModelsItem;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::PbxDeviceModels/;

sub allowed_methods{
    return [qw/GET OPTIONS HEAD PATCH PUT/];
}

1;

# vim: set tabstop=4 expandtab:
