package NGCP::Panel::Utils::Redis;

use warnings;
use strict;

use Redis;

sub get_redis_connection {
    my ($c, $params) = @_;
    my $redis = Redis->new(
        server => $c->config->{redis}->{central_url},
        reconnect => 10, every => 500000, # 500ms
        cnx_timeout => 3,
    );
    unless ($redis) {
        $c->log->error("Failed to connect to central redis url " . $c->config->{redis}->{central_url});
        return;
    }
    $redis->select($params->{database});
    return $redis;
}

1;
