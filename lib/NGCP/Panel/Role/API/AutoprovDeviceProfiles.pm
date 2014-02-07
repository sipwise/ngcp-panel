package NGCP::Panel::Role::API::AutoprovDeviceProfiles;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use Try::Tiny;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::Device::Profile;

sub get_form {
    my ($self, $c) = @_;

    return NGCP::Panel::Form::Device::Profile->new;
}

1;
# vim: set tabstop=4 expandtab:
