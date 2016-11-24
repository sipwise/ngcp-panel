package NGCP::Panel::Widget::Dashboard::AdminSystemOverview;

use warnings;
use strict;

use NGCP::Panel::Utils::Preferences;

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

sub emergency_mode {
    my ($self, $c) = @_;
    my $em_count = 0;
    foreach my $prov_dom($c->model('DB')->resultset('voip_domains')->all) {
        my $em_rs = NGCP::Panel::Utils::Preferences::get_dom_preference_rs(
            c => $c,
            attribute => 'emergency_mode_enabled',
            prov_domain => $prov_dom,
        );
        if($em_rs && $em_rs->first) {
            $c->log->debug("+++++ domain ".$prov_dom->domain." has emergency mode " . $em_rs->first->value);
            $em_count++;
        }
    }
    return $em_count;
}

1;
# vim: set tabstop=4 expandtab:
