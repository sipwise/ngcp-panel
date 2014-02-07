package NGCP::Panel::Role::API::AutoprovDeviceModels;
use Moose::Role;
use Sipwise::Base;

use boolean qw(true);
use Try::Tiny;
use Data::HAL qw();
use Data::HAL::Link qw();
use HTTP::Status qw(:constants);
use JSON::Types;
use NGCP::Panel::Form::Device::Model;
use NGCP::Panel::Form::Device::ModelAdmin;

sub get_form {
    my ($self, $c) = @_;

    if($c->user->roles eq "admin") {
        return NGCP::Panel::Form::Device::ModelAdmin->new;
    } elsif($c->user->roles eq "reseller") {
        return NGCP::Panel::Form::Device::Model->new;
    }
}

1;
# vim: set tabstop=4 expandtab:
