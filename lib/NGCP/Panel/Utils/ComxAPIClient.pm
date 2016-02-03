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
    my $sessions = $self->_resolve_collection_fast( '/sessions', $max_rows );
    if ('ARRAY' eq ref $sessions->{data} && @{ $sessions->{data} }) {
        for my $session (@{ $sessions->{data} }) {
            $session->{accounts} = $self->_resolve_collection_fast( $session->{accounts}{href} );
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
    for my $session_data ($self->get_sessions->{data}) {
        my $session_id = $session_data->{id};
        $resp = $ua->delete($self->host . "/sessions/id/$session_id");
        last if $resp->code >= 300;
    }
    return $resp;
}

sub get_users {
    my ($self, $max_rows) = @_;
    my $users = $self->_resolve_collection_fast( '/users', $max_rows );
    return $users;
}

sub get_networks {
    my ($self) = @_;
    my $networks = $self->_resolve_collection_fast( '/networks' );
    return $networks;
}

sub _resolve_collection {
    my ($self, $bare_url, $max_rows) = @_;
    my $ua = $self->ua;
    my $rel_url = $self->_strip_host( $bare_url );
    my $res = $ua->get($self->host . $rel_url);
    my @result;
    return {code => $res->code, response => $res} unless $res->code == 200;
    my $collection = JSON::decode_json($res->content);
    return {code => $res->code, response => $res,
        error_detail => 'could not decode_json'} unless $collection;
    my $item_res;
    for my $item (@{ $collection->{items} }) {
        last if (defined $max_rows && $max_rows-- <= 0);
        my $url = $self->_strip_host( $item->{href} );
        $item_res = $ua->get($self->host . $url);
        my $item_data = decode_json($item_res->content);
        push @result, $item_data;
    }
    return {
            response => $item_res,  # latest response
            code => $item_res->code,
            data => \@result,
            total_count => scalar(@result),
        };
}

sub _resolve_collection_fast {
    my ($self, $bare_url, $max_rows) = @_;
    my $ua = $self->ua;
    my $rel_url = $self->_strip_host( $bare_url );
    $rel_url =
        $rel_url .
        ( ($rel_url =~ m/\?/) ? '&' : '?' ) .
        'expand=true';
    my $res = $ua->get($self->host . $rel_url);
    my @result;
    return {code => $res->code, response => $res} unless $res->code == 200;
    my $collection = JSON::decode_json($res->content);
    return {code => $res->code, response => $res,
        error_detail => 'could not decode_json'} unless $collection;
    if ('HASH' eq ref $collection) {  # everything ok
        return {
                response => $res,
                code => $res->code,
                data =>  $collection->{items},
                total_count => $collection->{total} // (scalar @{ $collection->{items} }),
            };
    } else {  # unknown error
        return {
                response => $res,
                code => $res->code,
                data =>  $collection,
            };
    }
}

sub _strip_host {
    my ($self, $url) = @_;
    my $url_orig = $self->host;
    my $url_noip = $url_orig =~ s!:\d+!!r;
    my $fake_host = 'https://' .
        ($self->ua->default_header('Host') || "NONEXSISTENT");
    return $url =~ s!$url_orig|$url_noip|$fake_host!!r;
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
