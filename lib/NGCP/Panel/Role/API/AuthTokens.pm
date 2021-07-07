package NGCP::Panel::Role::API::AuthTokens;

use Sipwise::Base;
use NGCP::Panel::Utils::Redis;

use parent 'NGCP::Panel::Role::API';

use Redis;
use UUID;

sub get_form {
    my ($self, $c) = @_;
    return NGCP::Panel::Form::get("NGCP::Panel::Form::AuthToken", $c);
}

sub generate_auth_token {
    my ($self, $c, $resource) = @_;

    my ($uuid_bin, $uuid_string);
    UUID::generate($uuid_bin);
    UUID::unparse($uuid_bin, $uuid_string);
    #remove '-' from the token
    $uuid_string =~ s/\-//g;
    my $redis = NGCP::Panel::Utils::Redis::get_redis_connection($c, {database => $c->config->{'Plugin::Session'}->{redis_db}});
    return unless $redis;
    $redis->hset("auth_token:$uuid_string", 'type', $resource->{type});
    $redis->hset("auth_token:$uuid_string", 'role', $c->user->roles);
    $redis->hset("auth_token:$uuid_string", 'user_id', $c->user->id);
    $redis->expire("auth_token:$uuid_string", $resource->{expires});

    return $uuid_string;
}

1;
# vim: set tabstop=4 expandtab:
