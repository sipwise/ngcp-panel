package NGCP::Panel::Utils::DeviceBootstrap::Snom;

use strict;
use warnings;

use URI::Escape;
use Moo;
use Types::Standard qw(Str);
use JSON qw/encode_json decode_json/;
use MIME::Base64;
use Digest::MD5 qw/md5_hex/;
use Digest::SHA qw(hmac_sha256_base64);
use URI;
use TryCatch;
use Data::Dumper;
use Data::UUID;

extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorREST';

sub rpc_server_params {
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => 'secure-provisioning.snom.com',
        path     => 'api/v1',
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
    my $param_uri = $self->content_params->{uri};
    my $credentials = {
        id => $self->params->{credentials}->{user},
        key => $self->params->{credentials}->{password}
    };
    my $company_url;

    my $tx_id = $c->session->{api_request_tx_id} //
                uc Data::UUID->create_str() =~ s/-//gr;

    $self->{rpc_server_params} //= $self->rpc_server_params;
    my $cfg = $self->{rpc_server_params};

    $c->log->debug($self->to_log({ name   => 'Snom prepare request',
                                   tx_id  => $tx_id,
                                   action => $action }));

    # first, get company url --------------------------------------------------
    $op_name = 'Snom get tokens';
    $err = '';
    $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/tokens/".$credentials->{id};
    $c->log->debug($self->to_log({ name  => $op_name,
                                   tx_id => $tx_id,
                                   url   => $url }));
    ($data, $rc) = $self->send_request($c, $tx_id, $url, 'GET', $credentials);
    if ($rc == 0 && $data && ref $data eq 'HASH' && $data->{links}->{company}) {
        $company_url = $data->{links}->{company};
        $c->log->debug($self->to_log({ name   => $op_name,
                                       status => 'success',
                                       tx_id  => $tx_id,
                                       url    => $url,
                                       data   => $self->data_to_str($data) }));
        $url = $data->{links}->{company};
    } else {
        $rc = 1;
    }
    $c->log->debug($self->to_log({ name   => 'Snom get tokens',
                                   status => $rc ? 'failed' : 'success',
                                   tx_id  => $tx_id,
                                   url    => $url,
                                   data   => $self->data_to_str($data) }));
    return if $rc;
    #--------------------------------------------------------------------------

    if ($action eq 'register_content') {

        # get product groups --------------------------------------------------
        my ($product_group_id, $setting_id);
        $op_name = 'Snom get product groups';
        $err = '';
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/product-groups/";
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        ($data, $rc) = $self->send_request($c, $tx_id, $url, 'GET', $credentials);
        if ($rc == 0 && $data && ref $data eq 'ARRAY') {
            my ($product_group) = grep {$_->{name} eq $self->params->{redirect_params}->{product_family}} @$data;
            if ($product_group) {
                $product_group_id = $product_group->{uuid};
            }
            else {
                $err = 'specified product family not found';
                $rc = 1;
            }
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

        # get settings ---------------------------------------------------------
        $op_name = 'Snom get settings';
        $err = '';
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/settings/";
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        ($data, $rc) = $self->send_request($c, $tx_id, $url, 'GET', $credentials);
        if ($rc == 0 && $data && ref $data eq 'ARRAY') {
            foreach my $setting (@$data) {
                if ($setting->{param_name} eq 'setting_server') {
                    $setting_id = $setting->{uuid};
                    last;
                }
            }
            unless ($setting_id) {
                $err = 'setting for redirection server not found.';
                $rc = 1;
            }
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

        # fetch profile -------------------------------------------------------
        $op_name = 'Snom check profiles';
        $err = '';
        $url = "$company_url/provisioning-profiles/";
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        ($data, $rc) = $self->send_request($c, $tx_id, $url, 'GET', $credentials);
        if ($rc == 0 && $data && ref $data eq 'ARRAY') {
            # ok, noop
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

        # process profile -----------------------------------------------------
        my $profile_id;
        my ($profile) = grep {$_->{name} eq $self->params->{redirect_params}->{profile}} @$data;
        if ($profile) {
            $profile_id = $profile->{uuid};
        } elsif (length $self->params->{redirect_params}->{profile}) {
            #profile does not exist, create it
            $op_name = 'Snom create profile';
            $err = '';
            my $body = encode_json({
                name => $self->params->{redirect_params}->{profile},
                product_group  => $product_group_id,
                autoprovisioning_enabled => 'true',
            });
            my $body_ct = 'application/json';
            $c->log->debug($self->to_log({ name  => $op_name,
                                           tx_id => $tx_id,
                                           url   => $url,
                                           data  => $self->data_to_str($body) }));
            ($data, $rc) = $self->send_request($c, $tx_id, $url, 'POST', $credentials, $body_ct, $body);
            if ($rc == 0 && $data && ref $data eq 'HASH' && $data->{uuid}) {
                $profile_id = $data->{uuid};
            } else {
                $err = 'could not fetch profile uuid';
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
        $op_name = 'Snom prepare profile update (register)';
        $err = '';
        my $body = {
            mac => $new_mac,
            autoprovisioning_enabled => 'true',
            settings_manager => {
                $setting_id => {
                    value => $param_uri,
                    attrs => {
                        perm => 'RW'
                    }
                }
            }
        };

        $body->{provisioning_profile} = $profile_id if ($profile_id);
        $url = "$company_url/endpoints/$new_mac";
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        $ret = {
            method =>'PUT',
            url => $url,
            body => $body,
            hawk => $self->generate_header($url, 'PUT',
            {
                credentials => $credentials,
                content_type => '',
                payload => '',
            }),
        };
    } elsif ($action eq 'unregister_content') {
        # we've to fetch the id first before constructing the delete request --
        $op_name = 'Snom prepare profile delete (unregister)';
        $err = '';
        $url = "$company_url/endpoints/";
        $c->log->debug($self->to_log({ name  => $op_name,
                                       tx_id => $tx_id,
                                       url   => $url }));
        ($data, $rc) = $self->send_request($c, $tx_id, $url, 'GET', $credentials);
        if ($rc == 0 && $data && ref $data eq 'ARRAY') {
            my $device_id;
            my ($device) = grep {uc($_->{mac}) eq uc($old_mac)} @$data;
            if ($device) {
                $device_id = $device->{mac};
            }
            $url = "$company_url/endpoints/$device_id";
            $ret = {
                method =>'DELETE',
                url => $url,
                body => undef,
                hawk => $self->generate_header($url, 'DELETE',
                {
                    credentials => $credentials,
                    content_type => '',
                    payload => ''
                }),
            };
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

    unless ($ret) {
        $c->log->error($self->to_log({ name   => 'Snom prepare request',
                                       status => 'failed',
                                       tx_id  => $tx_id,
                                       msg    => 'no prepared register/unregister request' }));
    }

    return $ret;
}

sub to_log {
    my ($self, $data) = @_;

    my $msg = sprintf "%s:", $data->{name};
    foreach my $t (qw(tx_id action url status msg data)) {
        if (exists $data->{$t}) {
            $msg .= sprintf " $t=%s", $data->{$t} // '';
        }
    }

    return $msg;
}

sub send_request {
    my ($self, $c, $tx_id, $url, $method, $credentials, $body_ct, $body) = @_;

    my ($res, $data, $rc);
    my $req = HTTP::Request->new($method => $url);
    $req->header('Authorization' => $self->generate_header($url, $method,
                    {
                      credentials => $credentials,
                      content_type => '',
                      payload => ''
                    }
    ));
    $req->header('accept' => 'application/json');

    if ($method eq 'POST') {
        if ($body_ct) {
            $req->content_type($body_ct);
        }
        $req->content($body);
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

sub data_to_str {
    my ($self, $data) = @_;

    my $data_str;
    if (ref $data) {
        $data_str = Data::Dumper->new([$data])
                                ->Terse(1)
                                ->Dump;
    } elsif ($data) {
        $data_str = $data;
    }

    if ($data_str) {
        $data_str =~ s/\n//g;
        $data_str =~ s/\s+/ /g;
    } else {
        $data_str = '';
    }

    if (length($data_str) > 100000) {
        $data_str = "{ data => 'Msg size is too big' }";
    }

    return $data_str;
}

sub generate_header {
    my ($self, $uri, $method, $options) = @_;

    my $time = time;
    my $credentials = $options->{credentials};

    my @chars = ("A".."Z", "a".."z");
    my $nonce;
    $nonce .= $chars[rand @chars] for 1..8;

    $uri = URI->new($uri);

    my $hash = $self->calculate_payload_hash(
                    $options->{payload},
                    $options->{content_type},
                    $credentials->{key}
    );

    my $artifacts = {
        ts => $time,
        nonce => $nonce,
        method => $method,
        resource => $uri->path_query,
        host => $uri->host,
        port => $uri->port,
        hash => $hash || ''
    };

    my $mac = $self->calculate_mac($credentials, $artifacts);

    my $auth  = 'Hawk';
       $auth .= ' mac="' . $mac . '",';
       $auth .= ' hash="' . $artifacts->{hash} . '",' unless $hash eq '';
       $auth .= ' id="' . $credentials->{id} . '",';
       $auth .= ' ts="' . $artifacts->{ts} . '",';
       $auth .= ' nonce="' . $artifacts->{nonce} .'"';

    return $auth;

}

sub calculate_mac {
    my ($self, $credentials, $options) = @_;

    my $normalized = $self->generate_normalized_string($options);

    my $result_b64 = "";
    $result_b64 = hmac_sha256_base64($normalized, $credentials->{key});
    while (length($result_b64) % 4) {
        $result_b64 .= '=';
    }

    return $result_b64;
}

sub calculate_payload_hash {
    my ($self, $payload, $content_type, $key) = @_;

    return '' if $payload eq '';

    my $pload  = "hawk.1.payload\n";
       $pload .= $content_type . "\n";
       $pload .= ($payload || '');

    my $result_b64 = hmac_sha256_base64($pload, $key);

    while (length($result_b64) % 4) {
        $result_b64 .= '=';
    }

    return $result_b64;
}

sub generate_normalized_string {
    my ($self, $options) = @_;

    my $normalized = "hawk.1.header\n";
       $normalized .= $options->{ts}."\n";
       $normalized .= $options->{nonce}."\n";
       $normalized .= uc($options->{method}) . "\n";
       $normalized .= $options->{resource}."\n";
       $normalized .= $options->{host}."\n";
       $normalized .= $options->{port}."\n";
       $normalized .= "\n";
       $normalized .= "\n"; # this is also needed for a healthy header ( and mac ) since an extension is allowed in hawk

    return $normalized;
}

around 'process_bootstrap_uri' => sub {
    my($orig_method, $self, $uri) = @_;
    $uri = $self->$orig_method($uri);
    $uri = $self->bootstrap_uri_mac($uri, "{mac}");
    $self->content_params->{uri} = $uri;
    return $self->content_params->{uri};
};

1;
