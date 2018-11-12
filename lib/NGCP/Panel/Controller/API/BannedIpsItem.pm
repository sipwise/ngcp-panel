package NGCP::Panel::Controller::API::BannedIpsItem;

use parent qw/NGCP::Panel::Role::EntitiesItem NGCP::Panel::Role::API::BannedIps/;

use Sipwise::Base;


use HTTP::Status qw(:constants);
use NGCP::Panel::Utils::Security;


__PACKAGE__->set_config();

sub allowed_methods {
    return [qw/GET OPTIONS HEAD DELETE/];
}

sub delete_item {
    my($self, $c, $item, $old_resource, $resource, $form) = @_;
    my $ip = $item;
    NGCP::Panel::Utils::Security::ip_unban($c, $ip);
    return 1;
}

1;

# vim: set tabstop=4 expandtab:
