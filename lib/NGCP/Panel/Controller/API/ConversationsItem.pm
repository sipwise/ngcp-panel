package NGCP::Panel::Controller::API::ConversationsItem;

use Sipwise::Base;
use NGCP::Panel::Utils::Generic qw(:all);

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::Conversations/;

__PACKAGE__->set_config({
    apply_mandatory_parameters => 1,
    allowed_roles => [qw/admin reseller subscriberadmin subscriber/],
});

sub allowed_methods{
    return [qw/GET OPTIONS HEAD/];
}

1;

# vim: set tabstop=4 expandtab:
