package NGCP::Panel::Utils::DeviceBootstrap::ALE;

use strict;
use warnings;

use URI::Escape;
use Moo;
use Types::Standard qw(Str);
use JSON qw/encode_json decode_json/;
use MIME::Base64;
use Digest::MD5 qw/md5_hex/;

extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorREST';

sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => 'api.rps.ce.al-enterprise.com',
        path     => 'api',
    };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

sub rest_prepare_request {
    my ($self, $action) = @_;
    my $c = $self->params->{c};
    my $ret;
    my $new_mac = $self->content_params->{mac};
    my $old_mac = $self->content_params->{mac_old};
    my $param_servername = $self->content_params->{server_name};
    my $param_uri = $self->content_params->{uri};
    my $token;

    $self->{rpc_server_params} //= $self->rpc_server_params;
    my $cfg = $self->{rpc_server_params};

    $c->log->debug("ALE prepare request for action $action");

    # first, generate token
    my $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/bp_user/generate/token";
    $c->log->debug("ALE generate token '$url'");
    my $req = HTTP::Request->new(GET => $url);
    $req->header(':api_user_name' => $self->params->{credentials}->{user});
    $req->header(':api_password' => $self->params->{credentials}->{password});
    my $res = $self->_ua->request($req);

    my $data = decode_json($res->decoded_content);
    if ($res->is_success && $data->{success}) {
        $c->log->debug("Token generation successful, data: " . $res->decoded_content);
        $token = $data->{data}->{token};
        
        # $ret = {
        #     method =>'POST',
        #     url => "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/devices",
        #     body => { data => { mac => $new_mac, profile_id => $prof->{id}, url => undef} },
        # };
    } else {
        $c->log->error("Token generation failed (" . $res->status_line . "): " . $res->decoded_content);
        return;
    }

    if ($action eq 'register_content') {
        # fetch server
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/servers";
        $c->log->debug("ALE check server '$url'");
        $req = HTTP::Request->new(GET => $url);
        $req->header(token => $token);
        $res = $self->_ua->request($req);

        my $server_id;
        $data = decode_json($res->decoded_content);
        if ($res->is_success && $data->{success}) {
            $c->log->debug("ALE check server query successful, data: " . $res->decoded_content);
            my ($server) = grep {$_->{server_url} eq $param_uri} @{$data->{data}->{server_list}};
            if ($server) {
                $server_id = $server->{server_id};
            }
            else {
                #server does not exist, create it
                $c->log->debug("ALE create server '$url'");
                $req = HTTP::Request->new(POST => $url);
                $req->header(token => $token);
                $req->content_type('application/json');
                $req->content(encode_json({
                        server_name => $param_servername,
                        server_url  => $param_uri,
                    })
                );
                $res = $self->_ua->request($req);
                $data = decode_json($res->decoded_content);
                if ($res->is_success && $data->{success}) {
                    $c->log->debug("ALE create server query successful, data: " . $res->decoded_content);
                    $server_id = $data->{data}->{server_id};
                }
                else{
                    $c->log->error("ALE create server query failed (" . $res->status_line . "): " . $res->decoded_content);
                    return;
                }
            }
        } else {
            $c->log->error("ALE check server query failed (" . $res->status_line . "): " . $res->decoded_content);
            return;
        }

        # fetch profile
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/profiles";
        $c->log->debug("ALE check server '$url'");
        $req = HTTP::Request->new(GET => $url);
        $req->header(token => $token);
        $res = $self->_ua->request($req);

        $data = decode_json($res->decoded_content);
        if ($res->is_success && $data->{success}) {
            $c->log->debug("ALE check profile query successful, data: " . $res->decoded_content);
            my $profile_id;
            my ($profile) = grep {$_->{server_id} == $server_id} @{$data->{data}->{profile_list}};
            if ($profile) {
                $profile_id = $profile->{profile_id};
            }
            else {
                #profile does not exist, create it
                $c->log->debug("ALE create profile '$url'");
                $req = HTTP::Request->new(POST => $url);
                $req->header(token => $token);
                $req->content_type('application/json');
                $req->content(encode_json({
                        profile_name => $param_servername,
                        server_id  => $server_id,
                    })
                );
                $res = $self->_ua->request($req);
                $data = decode_json($res->decoded_content);
                if ($res->is_success && $data->{success}) {
                    $c->log->debug("ALE create profile query successful, data: " . $res->decoded_content);
                    $profile_id = $data->{data}->{profile_id};
                }
                else{
                    $c->log->error("ALE create profile query failed (" . $res->status_line . "): " . $res->decoded_content);
                    return;
                }
            }
            
            $ret = {
                method =>'POST',
                url => "$$cfg{proto}://$$cfg{host}/$$cfg{path}/devices",
                body => { macs => [{mac =>$new_mac}], profile_id => $profile_id},
                token => $token,
            };
        } else {
            $c->log->error("ALE check profile query failed (" . $res->status_line . "): " . $res->decoded_content);
            return;
        }
    } elsif ($action eq 'unregister_content') {
        # we've to fetch the id first before constructing the delete request
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/devices";
        $c->log->debug("ALE check devices '$url'");
        $req = HTTP::Request->new(GET => $url);
        $req->header(token => $token);
        $res = $self->_ua->request($req);
        $data = decode_json($res->decoded_content);
        if ($res->is_success && $data->{success}) {
            $c->log->debug("ALE check devices query successful, data: " . $res->decoded_content);
            my $device_id;
            my ($device) = grep {$_->{mac} == $old_mac} @{$data->{data}->{device_list}};
            if ($device) {
                $device_id = $device->{device_id};
            }
            $c->log->debug("ALE unregister query successful, data: " . $res->decoded_content);
            $data = decode_json($res->decoded_content);
            $ret = {
                method =>'DELETE',
                url => "$$cfg{proto}://$$cfg{host}/$$cfg{path}/devices/$device_id",
                body => undef,
                token => $token,
            };
        } else {
            $c->log->error("ALE unregister query failed (" . $res->status_line . "): " . $res->decoded_content);
            return;
        }
    }

    return $ret;
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
