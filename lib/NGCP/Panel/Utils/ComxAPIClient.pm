package NGCP::Panel::Utils::ComxAPIClient;

use warnings;
use strict;

use Moo;
# use Digest::MD5 qw/md5_hex/;
# use HTTP::Tiny;
# use Storable qw/freeze/;
use Types::Standard qw(Int HashRef);
# with 'Role::REST::Client';
use LWP::UserAgent;
use JSON qw/decode_json encode_json/;

has 'ua' => ( is => 'rw', default => sub {
        return LWP::UserAgent->new(
            ssl_opts => { verify_hostname => 0 },
            timeout => 20,
        );
    });

has 'host' => (is => 'rw', default => 'https://www.api-cdk.tld:8191');

has 'login_status' => (is => 'rw', 
        #isa => 'HTTP::Response',
        default => sub {return {};},
    );

sub mytest {
    my $c = NGCP::Panel::Utils::ComxAPIClient->new(
        host => 'https://rtcengine.sipwise.com/rtcengine/api',
    );
    $c->login('gjungwirth@sipwise', '***', 'rtcengine.sipwise.com:443');
    #p $c->get_sessions;
    #p $c->create_session_and_account('npa4V0YkavioQ1GW7Yob', 'sip', 'user1@bar.com', '123456', 'YAqON76yLVtgMgBYeg6v');
    #p $c->create_session_and_account('npa4V0YkavioQ1GW7Yob', 'sip4', 'sip:alice@192.168.51.150', 'alicepass', 'YAqON76yLVtgMgBYeg6v');
    #p $c->get_networks;
    $c->create_network('sip', 'sip-connector', {xms => JSON::false}, 'YAqON76yLVtgMgBYeg6v');
    print "done\n";
    return;
}

# returns appid or 0
sub login {
    my ( $self, $username, $password, $netloc ) = @_;
    my $ua = $self->ua;
    $netloc //= $self->host =~ s!^https?://(.*:[0-9]*)(/.*$|$)!$1!r;
    $ua->credentials($netloc, "ComX", $username, $password);
    my $resp = $ua->get($self->host . '/users');
    $self->login_status( $self->_create_response($resp) );
    return;
}

sub create_session_and_account {
    my ($self, $appid, $network, $identifier, $accessToken, $owner) = @_;
    my $ua = $self->ua;
    my $session_content = encode_json({
        app => $appid,
        owner => $owner,
        });
    my $session = $self->_create_response(
        $ua->post($self->host . '/sessions', 'Content-Type' => 'application/json', Content => $session_content),
        );
    my $account_content = encode_json({
        session => $session->{data}{id},
        network => $network,
        identifier => $identifier,
        accessToken => $accessToken,
        owner => $owner,
        });
    #p $account_content;
    my $account = $self->_create_response(
        $ua->post($self->host . '/accounts', 'Content-Type' => 'application/json', Content => $account_content),
        );
    $account->{data}{session} = $session->{data};
    return $account;
}

sub create_network {
    my ($self, $tag, $connector, $config, $owner) = @_;
    my $ua = $self->ua;
    my $network_content = encode_json({
        tag => $tag,
        connector => $connector,
        config => encode_json($config),
        owner => $owner,
        });
    my $network = $self->_create_response(
        $ua->post($self->host . '/networks', 'Content-Type' => 'application/json', Content => $network_content),
        );
    return $network;
}

sub create_user {
    my ($self, $email, $password) = @_;
    my $ua = $self->ua;
    my $user_content = encode_json({
            email => $email,
            password => $password,
        });
    my $user = $self->_create_response(
        $ua->post($self->host . '/users', 'Content-Type' => 'application/json', Content => $user_content),
        );
    return $user;
}

sub delete_network {
    my ($self, $network_id) = @_;
    my $ua = $self->ua;
    $network_id //= "";
    my $resp;
    $resp = $ua->delete($self->host . "/networks/id/$network_id");
    return $self->_create_response($resp);
}

sub delete_user {
    my ($self, $user_id) = @_;
    my $ua = $self->ua;
    $user_id //= "";
    my $resp;
    $resp = $ua->delete($self->host . "/users/id/$user_id");
    return $self->_create_response($resp);
}

sub delete_app {
    my ($self, $app_id) = @_;
    my $ua = $self->ua;
    $app_id //= "";
    my $resp;
    $resp = $ua->delete($self->host . "/apps/id/$app_id");
    return $self->_create_response($resp);
}

sub create_app {
    my ($self, $name, $domain, $owner) = @_;
    my $ua = $self->ua;
    my $app_content = encode_json({
        name => $name,
        domain => $domain,
        owner => $owner,
        });
    my $app = $self->_create_response(
        $ua->post($self->host . '/apps', 'Content-Type' => 'application/json', Content => $app_content),
        );
    return $app;
}

sub get_sessions {
    my ($self, $max_rows) = @_;
    my $sessions = $self->_resolve_collection( '/sessions', $max_rows );
    if ('ARRAY' eq ref $sessions && @{ $sessions }) {
        for my $session (@{ $sessions }) {
            $session->{accounts} = $self->_resolve_collection( $session->{accounts}{href} );
        }
    }
    return $sessions;
}

sub get_session {
    my ($self, $session_id) = @_;
    my $ua = $self->ua;

    return $self->_create_response(
        $ua->get($self->host . "/sessions/id/$session_id")
    );
}

sub delete_all_sessions {
    my ($self) = @_;
    my $ua = $self->ua;
    my $resp;
    for my $session_data ($self->get_sessions) {
        my $session_id = $session_data->{id};
        $resp = $ua->delete($self->host . "/sessions/id/$session_id");
        last if $resp->code >= 300;
    }
    return $resp;
}

sub get_users {
    my ($self, $max_rows) = @_;
    my $users = $self->_resolve_collection( '/users', $max_rows );
    return $users;
}

sub get_networks {
    my ($self) = @_;
    my $networks = $self->_resolve_collection( '/networks' );
    return $networks;
}

sub _resolve_collection {
    my ($self, $bare_url, $max_rows) = @_;
    my $ua = $self->ua;
    my $rel_url = $self->_strip_host( $bare_url );
    my $res = $ua->get($self->host . $rel_url);
    my @result;
    return [] unless $res->code == 200;
    my $collection = JSON::decode_json($res->content);
    return [] unless $collection;
    for my $item (@{ $collection->{items} }) {
        last if (defined $max_rows && $max_rows-- <= 0);
        my $url = $self->_strip_host( $item->{href} );
        my $item_res = $ua->get($self->host . $url);
        my $item_data = decode_json($item_res->content);
        push @result, $item_data;
    }
    return \@result;
}

sub _strip_host {
    my ($self, $url) = @_;
    my $url_orig = $self->host;
    my $url_noip = $url_orig =~ s!:\d+!!r;
    return $url =~ s!$url_orig|$url_noip!!r;
}

sub _create_response {
    my ($self, $res) = @_;
    my $data;
    if ($res->is_success && $res->content) {
        $data = decode_json($res->content);
    }
    return {
        code => $res->code,
        data => $data,
        response => $res,
    };
}


1;

# vim: set tabstop=4 expandtab:
