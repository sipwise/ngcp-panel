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
            $c->log->debug("The domain ".$prov_dom->domain." has emergency mode " . $em_rs->first->value);
            $em_count++;
        }
    }
    return $em_count.'';
}

sub overall_status {
    my ($self, $c) = @_;

    my $report = decode_json(NGCP::Panel::Utils::Statistics::get_ngcp_status());

    my $status_level = lc $report->{system_status};
    my %status_map = (
        errors => {
            class => 'ngcp-red-error',
            text => $c->loc('Errors'),
        },
        warnings => {
            class => 'ngcp-orange-warning',
            text => $c->loc('Warnings'),
        },
        ok => {
            class => 'ngcp-green-ok',
            text => $c->loc('All services running'),
        },
    );
    my $status = $status_map{$status_level};
    $status->{problems} = $report->{problems} if $status_level ne 'ok';

    return $status;
}

1;
# vim: set tabstop=4 expandtab:
