package NGCP::Panel::Utils::DeviceBootstrap::ALE;

use strict;
use warnings;

use URI::Escape;
use Moo;
use Types::Standard qw(Str);
use JSON qw/encode_json decode_json/;
use MIME::Base64;
use Digest::MD5 qw/md5_hex/;
use TryCatch;

extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorREST';

sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => 'api.eds.al-enterprise.com',
        path     => 'api',
    };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

sub rest_prepare_request {
    my ($self, $action) = @_;
    my $c = $self->params->{c};
    my ($op_name, $url, $ret, $res, $data, $rc, $err);
    my $new_mac = $self->content_params->{mac};
    my $old_mac = $self->content_params->{mac_old};
    my $param_servername = $self->content_params->{server_name};
    my $param_uri = $self->content_params->{uri};
    my $token;

    $self->{rpc_server_params} //= $self->rpc_server_params;
    my $cfg = $self->{rpc_server_params};

    my $tx_id = $c->session->{api_request_tx_id} //
                uc Data::UUID->create_str() =~ s/-//gr;

    $c->log->debug($self->to_log({ name   => 'ALE prepare request',
                                   tx_id  => $tx_id,
                                   action => $action }));

    # first, generate token ---------------------------------------------------
    $op_name = 'ALE generate token';
    $err = '';
    $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/bp_user/generate/token";
    $c->log->debug($self->to_log({ name  => $op_name,
                                   tx_id => $tx_id,
                                   url   => $url }));
    ($data, $rc) = $self->send_http_request($c, $tx_id, $url, 'GET');
    if ($rc == 0 && $data && ref $data eq 'HASH' && $data->{success}) {
        $token = $data->{data}->{token};
    } else {
        $rc = 1;
    }
    $c->log->debug($self->to_log({ name   => $op_name,
                                   status => $rc ? 'failed' : 'success',
                                   tx_id  => $tx_id,
                                   url    => $url,
                                   data   => $self->data_to_str($data) }));
    return if $rc;
    # -------------------------------------------------------------------------

    if ($action eq 'register_content') {
        # check server --------------------------------------------------------
        my $server_id;
        $op_name = 'ALE check server';
        $err = '';
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/servers";
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        ($data, $rc) = $self->send_http_request($c, $tx_id, $url, 'GET', $token);
        if ($rc == 0 && $data && ref $data eq 'HASH' && $data->{success}) {
            my ($server) = grep {$_->{server_url} eq $param_uri} @{$data->{data}->{server_list}};
            if ($server) {
                $server_id = $server->{server_id};
            }
        }
        $c->log->debug($self->to_log({ name   => $op_name,
                                       status => $rc ? 'failed' : 'success',
                                       tx_id  => $tx_id,
                                       url    => $url,
                                       msg    => $err // '',
                                       data   => $self->data_to_str($data) }));
        return if $rc;

        # server does not exist, create it ------------------------------------
        unless ($server_id) {
            $op_name = 'ALE create server';
            $err = '';
            my $body_ct = 'application/json';
            my $body    = encode_json({
                    server_name => $param_servername,
                    server_url  => $param_uri,
            });
            $c->log->debug($self->to_log({ name  => $op_name,
                                           tx_id => $tx_id,
                                           url   => $url,
                                           data  => $self->data_to_str($body) }));
            ($data, $rc) = $self->send_http_request($c, $tx_id, $url, 'POST', $token, $body_ct, $body);
            if ($rc == 0 && $data && ref $data eq 'HASH' && $data->{success}) {
                $server_id = $data->{data}->{server_id};
            } else {
                $rc = 1;
            }
            $c->log->debug($self->to_log({ name   => $op_name,
                                           status => $rc ? 'failed' : 'success',
                                           tx_id  => $tx_id,
                                           url    => $url,
                                           msg    => $err // '',
                                           data   => $self->data_to_str($data) }));
            return if $rc;
        }

        # fetch profile -------------------------------------------------------
        my $profile_id;
        $op_name = 'ALE check profile';
        $err = '';
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/profiles";
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        ($data, $rc) = $self->send_http_request($c, $tx_id, $url, 'GET', $token);
        if ($rc == 0 && $data && ref $data eq 'HASH' && $data->{success}) {
            my ($profile) = grep {$_->{server_id} == $server_id} @{$data->{data}->{profile_list}};
            if ($profile) {
                $profile_id = $profile->{profile_id};
            }
        }
        $c->log->debug($self->to_log({ name   => $op_name,
                                       status => $rc ? 'failed' : 'success',
                                       tx_id  => $tx_id,
                                       url    => $url,
                                       msg    => $err // '',
                                       data   => $self->data_to_str($data) }));
        return if $rc;

        unless ($profile_id) {
            # profile does not exist, create it -------------------------------
            $op_name = 'ALE create profile';
            $err = '';
            my $body_ct = 'application/json';
            my $body    = encode_json({
                    profile_name => $param_servername,
                    server_id  => $server_id,
            });
            $c->log->debug($self->to_log({ name  => $op_name,
                                           tx_id => $tx_id,
                                           url   => $url,
                                           data  => $self->data_to_str($body) }));
            ($data, $rc) = $self->send_http_request($c, $tx_id, $url, 'POST', $token, $body_ct, $body);
            if ($rc == 0 && $data && ref $data eq 'HASH' && $data->{success}) {
                $profile_id = $data->{data}->{profile_id};
            } else {
                $rc = 1;
            }
            $c->log->debug($self->to_log({ name   => $op_name,
                                           status => $rc ? 'failed' : 'success',
                                           tx_id  => $tx_id,
                                           url    => $url,
                                           msg    => $err // '',
                                           data   => $self->data_to_str($data) }));
            return if $rc;
        }

        # update profile ------------------------------------------------------
        $op_name = 'ALE prepare profile update (register)';
        $err = '';
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        $ret = {
            method =>'POST',
            url => "$$cfg{proto}://$$cfg{host}/$$cfg{path}/devices",
            body => { macs => [{mac =>$new_mac}], profile_id => $profile_id},
            token => $token,
        };
    } elsif ($action eq 'unregister_content') {
        # we've to fetch the id first before constructing the delete request --
        my $device_id;
        $op_name = 'ALE prepare profile delete (unregister)';
        $err = '';
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/devices";
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        ($data, $rc) = $self->send_http_request($c, $tx_id, $url, 'GET', $token);
        if ($rc == 0 && $data && ref $data eq 'HASH' && $data->{success}) {
            my ($device) = grep {uc $_->{mac} eq uc $old_mac} @{$data->{data}->{device_list}};
            if ($device) {
                $device_id = $device->{device_id};
            }
        }
        unless ($device_id) {
            $err = 'missing device_id';
            $rc = 1;
        }
        $c->log->debug($self->to_log({ name   => $op_name,
                                       status => $rc ? 'failed' : 'success',
                                       tx_id  => $tx_id,
                                       url    => $url,
                                       msg    => $err // '',
                                       data   => $self->data_to_str($data) }));
        return if $rc;

        $ret = {
            method =>'DELETE',
            url => "$$cfg{proto}://$$cfg{host}/$$cfg{path}/devices/$device_id",
            body => undef,
            token => $token,
        };
    }

    unless ($ret) {
        $c->log->error($self->to_log({ name   => 'ALE prepare request',
                                       status => 'failed',
                                       tx_id  => $tx_id,
                                       msg    => 'no prepared register/unregister request' }));
    }

    return $ret;
}

sub send_http_request {
    my ($self, $c, $tx_id, $url, $method, $token, $body_ct, $body) = @_;

    my ($res, $data, $rc);
    my $req = HTTP::Request->new($method => $url);

    unless ($token) {
        $req->header(':api_user_name' => $self->params->{credentials}->{user});
        $req->header(':api_password' => $self->params->{credentials}->{password});
    } else {
        $req->header('token' => $token);
    }

    $req->header('accept' => 'application/json');

    if ($method eq 'POST') {
        $req->content_type($body_ct) if $body_ct;
        $req->content($body) if $body;
    }

    $res = $self->_ua->request($req);
    if ($res->is_success) {
        if ($res->decoded_content) {
            try {
                $data = decode_json($res->decoded_content);
            } catch($e) {
                $c->log->error($self->to_log({ name   => 'Failed to parse JSON content',
                                               status => 'failed',
                                               tx_id  => $tx_id,
                                               url    => $url,
                                               msg    => $e,
                                               data   => $self->data_to_str($res->decoded_content) }));
                return ($data, 1);
            };
        }
    } else {
        $c->log->error($self->to_log({ name   => "$method reqeuest",
                                       status => 'failed',
                                       tx_id  => $tx_id,
                                       url    => $url,
                                       msg    => $res->status_line,
                                       data   => $self->data_to_str($res->decoded_content) }));
        return ($data, 1);
    }

    return ($data, 0);
}

around 'process_bootstrap_uri' => sub {
    my($orig_method, $self, $uri) = @_;
    $uri = $self->$orig_method($uri);
    $self->content_params->{uri} = $uri;
    $self->bootstrap_uri_server_name($uri);
    return $self->content_params->{uri};
};

sub bootstrap_uri_server_name{
    my($self,$uri) = @_;
    $uri ||= $self->content_params->{uri};
    #http://stackoverflow.com/questions/4826403/hash-algorithm-with-alphanumeric-output-of-20-characters-max
    $self->content_params->{server_name} ||= substr(md5_hex($uri),0,20);
    return $self->content_params->{server_name};
}

1;
