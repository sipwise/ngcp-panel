package NGCP::Panel::Controller::API::BannedUsersItem;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::BannedUsers/;

use Sipwise::Base;


use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Security;


__PACKAGE__->set_config();

sub allowed_methods {
    return [qw/GET OPTIONS HEAD DELETE/];
}

sub delete_item {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;
    my $user = $item;
    NGCP::Panel::Utils::Security::ip_unban($c, $user);
    #foreach my $p ($item->voip_peer_hosts->all) {
    #    $p->voip_peer_preferences->delete_all;
    #    $p->delete;
    #}
    #$item->delete;
    #NGCP::Panel::Utils::Peering::_sip_lcr_reload(c => $c);
}

1;

# vim: set tabstop=4 expandtab:
