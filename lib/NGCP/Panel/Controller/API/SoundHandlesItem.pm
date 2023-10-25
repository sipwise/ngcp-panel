package NGCP::Panel::Controller::API::SoundHandlesItem;
use NGCP::Panel::Utils::Generic qw(:all);

use Sipwise::Base;

use HTTP::Headers qw();
use HTTP::Status qw(:constants);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::SoundHandles/;

__PACKAGE__->set_config({
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

1;

# vim: set tabstop=4 expandtab:
