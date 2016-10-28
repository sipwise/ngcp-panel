package NGCP::Panel::Controller::API::SMSItem;

use Sipwise::Base;
use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SMS/;

use HTTP::Status qw(:constants);


__PACKAGE__->set_config();

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

use parent qw/Catalyst::Controller NGCP::Panel::Role::API::CFSourceSets/;

1;

# vim: set tabstop=4 expandtab:
