package NGCP::Panel::Utils::NCOS;
use strict;
use warnings;

use English;
use NGCP::Panel::Utils::Preferences;

sub revoke_exposed_ncos_level {
    my ($c, $ncos_level_id) = @_;

    my $used_contract_prefs_rs = $c->model('DB')->resultset('voip_contract_preferences')->search({
        'attribute.attribute' => 'ncos_id',
        value => $ncos_level_id,
    },{
        join => 'attribute',
    });
    $used_contract_prefs_rs->delete;

    my $used_subscriber_prefs_rs = $c->model('DB')->resultset('voip_usr_preferences')->search({
        'attribute.attribute' => 'ncos_id',
        value => $ncos_level_id,
    },{
        join => 'attribute',
    });
    $used_subscriber_prefs_rs->delete;
}

1;

# vim: set tabstop=4 expandtab:
