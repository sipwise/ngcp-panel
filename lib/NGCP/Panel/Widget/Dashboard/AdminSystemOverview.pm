package NGCP::Panel::Widget::Dashboard::AdminSystemOverview;

use warnings;
use strict;

use NGCP::Panel::Utils::Preferences;
use NGCP::Panel::Utils::Statistics;
use JSON qw(decode_json);

sub template {
    return unless NGCP::Panel::Utils::Statistics::has_ngcp_status();
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
        if($em_rs && $em_rs->first && int($em_rs->first->value) > 0) {
            $c->log->debug("+++++ domain ".$prov_dom->domain." has emergency mode " . $em_rs->first->value);
            $em_count++;
        }
    }
    return $em_count.'';
}

sub overall_status {
    my ($self, $c) = @_;

    my $ngcp_status = decode_json(NGCP::Panel::Utils::Statistics::get_ngcp_status());
    return { class => "ngcp-red-error", text => $c->loc("Errors"), data => $ngcp_status->{data} } if ( $ngcp_status->{system_status} eq 'ERRORS' );
    return { class => "ngcp-orange-warning", text => $c->loc("Warnings"), , data => $ngcp_status->{data} } if ( $ngcp_status->{system_status} eq 'WARNINGS' );
    return { class => "ngcp-green-ok", text => $c->loc("All services running") };
}

1;
# vim: set tabstop=4 expandtab:
