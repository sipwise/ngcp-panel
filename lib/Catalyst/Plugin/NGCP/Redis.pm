package Catalyst::Plugin::NGCP::Redis;
use strict;
use warnings;
use MRO::Compat;
use Redis;
use Try::Tiny;

my $conn = {};

sub redis_get_connection {
    my ($c, $params) = @_;
    my $db = $params->{database} // return;
    my $conn_ref;

    try {
        $conn_ref = $conn->{$db} // _connect_and_cache($c, $params);
        _wait_for_master_role($conn_ref);
    } catch {
        $conn_ref = _connect_and_cache($c, $params) // return;
        _wait_for_master_role($conn_ref);
    };

    return $conn_ref;
}

sub _connect_and_cache {
    my ($c, $params) = @_;
    my $db = $params->{database} // return;

    my $conn_ref = Redis->new(
        server => $c->config->{redis}->{central_url},
        reconnect => 10, every => 500000, # 500ms
        cnx_timeout => 3,
    ) or do {
        $c->log->error("Failed to connect to redis url " . $c->config->{redis}->{central_url});
        return;
    };

    $conn_ref->select($params->{database});
    $conn->{$db} = $conn_ref;

    return $conn_ref;
}

sub _wait_for_master_role {
    my $conn_ref = shift;

    my $cnt = 0;
    my $interval = 1;
    my $wait = 5;

    while ($cnt < $wait) {
        return 1 if _get_replication_role($conn_ref) eq 'master';
        sleep $interval;
        $cnt += $interval;
    }

    return;
}

sub _get_replication_role {
    my $conn_ref = shift;

    my $repl_info = $conn_ref->info('replication');

    return ref $repl_info eq 'HASH' ? $repl_info->{role} : '';
}

1;
