package NGCP::Panel::Widget::Dashboard::AdminSystemOverview;

use warnings;
use strict;

sub template {
    return 'widgets/admin_system_overview.tt';
}

sub filter {
    my ($self, $c) = @_;

    return 1 if(
        $c->user->roles eq 'admin'
    );
    return;
}

1;
# vim: set tabstop=4 expandtab:
