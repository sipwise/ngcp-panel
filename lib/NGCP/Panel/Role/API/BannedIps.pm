package NGCP::Panel::Role::API::BannedIps;

use Sipwise::Base;


use parent qw/NGCP::Panel::Role::API/;

use NGCP::Panel::Utils::Generic qw(:all);
use boolean qw(true);
use HTTP::Status qw(:constants);
use NGCP::Panel::Form::Peering::Group;
use NGCP::Panel::Utils::Peering;

sub item_name {
    return 'bannedips';
}

sub resource_name{
    return 'bannedips';
}

1;
# vim: set tabstop=4 expandtab:
