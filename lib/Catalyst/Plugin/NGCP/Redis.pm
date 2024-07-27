package Catalyst::Plugin::NGCP::Redis;
use strict;
use warnings;
use MRO::Compat;
use Redis;

my $conn = {};

sub redis_get_connection {
    my ($c, $params) = @_;

    my $db = $params->{database} // return;
    my $redis;
    $redis = $conn->{$db} // do {
        $redis = Redis->new(
            server => $c->config->{redis}->{central_url},
            reconnect => 10, every => 500000, # 500ms
            cnx_timeout => 3,
        );
        unless ($redis) {
            $c->log->error("Failed to connect to central redis url " . $c->config->{redis}->{central_url});
            return;
        }
        $redis->select($params->{database});
        $conn->{$db} = $redis;
    };

    return $redis;
}

1;
