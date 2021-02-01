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

extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorREST';

sub rpc_server_params{
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
    my $ret;
    my $new_mac = $self->content_params->{mac};
    my $old_mac = $self->content_params->{mac_old};
    my $param_uri = $self->content_params->{uri};
    my $credentials = {
        id => $self->params->{credentials}->{user},
        key => $self->params->{credentials}->{password}
    };

    $self->{rpc_server_params} //= $self->rpc_server_params;
    my $cfg = $self->{rpc_server_params};

    $c->log->debug("Snom prepare request for action $action");

    # first, get company url
    my $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/tokens/".$credentials->{id};
    $c->log->debug("Snom get tokens '$url'");
    my $req = HTTP::Request->new(GET => $url);
    $req->header('Authorization' => $self->generate_header($url, "GET", { credentials => $credentials, content_type => '', payload => '' }));
    $req->header('accept' => 'application/json');
    my $res = $self->_ua->request($req);
    my $data = decode_json($res->decoded_content);
    my $company_url = $data->{links}->{company};
    if ($res->is_success && $data->{links}->{company}) {
        $c->log->debug("Tokens fetching successful, data: " . $res->decoded_content);
        $url = $data->{links}->{company};
    } else {
        $c->log->error("Tokens fetching failed (" . $res->status_line . "): " . $res->decoded_content);
        return;
    }

    if ($action eq 'register_content') {
        # fetch product groups
        $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/product-groups/";
        $c->log->debug("Snom fetch product groups '$url'");
        $req = HTTP::Request->new(GET => $url);
        $req->header('Authorization' => $self->generate_header($url, "GET", { credentials => $credentials, content_type => '', payload => '' }));
        $req->header('accept' => 'application/json');
        $res = $self->_ua->request($req);

        my $product_group_id;
        my $setting_id;
        $data = decode_json($res->decoded_content);
        if ($res->is_success && scalar @$data) {
            $c->log->debug("Snom fetch product groups successful, data: " . $res->decoded_content);
            my ($product_group) = grep {$_->{name} eq $self->params->{redirect_params}->{product_family}} @$data;
            if ($product_group) {
                $product_group_id = $product_group->{uuid};
            }
            else {
                $c->log->error("Snom product group of specified product family not found.");
                return;
            }

            #fetch settings
            $url = "$$cfg{proto}://$$cfg{host}/$$cfg{path}/settings/";
            $c->log->debug("Snom fetch settings '$url'");
            $req = HTTP::Request->new(GET => $url);
            $req->header('Authorization' => $self->generate_header($url, "GET", { credentials => $credentials, content_type => '', payload => '' }));
            $req->header('accept' => 'application/json');
            $res = $self->_ua->request($req);

            $data = decode_json($res->decoded_content);
            if ($res->is_success && scalar @$data) {
                $c->log->debug("Snom fetch settings successful, data: " . $res->decoded_content);
                foreach my $setting (@$data) {
                    if ($setting->{param_name} eq 'setting_server') {
                        $setting_id = $setting->{uuid};
                    }
                }
                unless ($setting_id) {
                    $c->log->error("Snom setting for redirection server not found.");
                    return;
                }
            }
        } else {
            $c->log->error("Snom fetch product groups quey failed (" . $res->status_line . "): " . $res->decoded_content);
            return;
        }

        # fetch profile
        $url = "$company_url/provisioning-profiles/";
        $c->log->debug("Snom check profiles '$url'");
        $req = HTTP::Request->new(GET => $url);
        $req->header('Authorization' => $self->generate_header($url, "GET", { credentials => $credentials, content_type => '', payload => '' }));
        $req->header('accept' => 'application/json');
        $res = $self->_ua->request($req);

        $data = decode_json($res->decoded_content);
        if ($res->is_success && scalar @$data) {
            $c->log->debug("Snom check profiles query successful, data: " . $res->decoded_content);
            my $profile_id;
            my ($profile) = grep {$_->{name} eq $self->params->{redirect_params}->{profile}} @$data;
            if ($profile) {
                $profile_id = $profile->{uuid};
            }
            elsif (length $self->params->{redirect_params}->{profile}) {
                #profile does not exist, create it
                $c->log->debug("Snom create profile '$url'");
                $req = HTTP::Request->new(POST => $url);
                my $body = encode_json({
                    name => $self->params->{redirect_params}->{profile},
                    product_group  => $product_group_id,
                    autoprovisioning_enabled => 'true',
                });
                $req->header('Authorization' => $self->generate_header($url, "POST", { credentials => $credentials, content_type => '', payload => '' }));
                $req->header('accept' => 'application/json');
                $req->content_type('application/json');
                $req->content($body);
                $res = $self->_ua->request($req);
                $data = decode_json($res->decoded_content);
                if ($res->is_success && $res->code == 201) {
                    $c->log->debug("Snom create profile query successful, data: " . $res->decoded_content);
                    $profile_id = $data->{uuid};
                }
                else{
                    $c->log->error("Snom create profile query failed (" . $res->status_line . "): " . $res->decoded_content);
                    return;
                }
            }

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
            $ret = {
                method =>'PUT',
                url => $url,
                body => $body,
                hawk => $self->generate_header($url, "PUT", { credentials => $credentials, content_type => '', payload => '' }),
            };
        } else {
            $c->log->error("Snom check profile query failed (" . $res->status_line . "): " . $res->decoded_content);
            return;
        }
    } elsif ($action eq 'unregister_content') {
        # we've to fetch the id first before constructing the delete request
        $url = "$company_url/endpoints/";
        $c->log->debug("Snom check devices '$url'");
        $req = HTTP::Request->new(GET => $url);
        $req->header('Authorization' => $self->generate_header($url, "GET", { credentials => $credentials, content_type => '', payload => '' }));
        $req->header('accept' => 'application/json');
        $res = $self->_ua->request($req);
        $data = decode_json($res->decoded_content);
        if ($res->is_success && scalar @$data) {
            $c->log->debug("Snom check devices query successful, data: " . $res->decoded_content);
            my $device_id;
            my ($device) = grep {uc($_->{mac}) eq uc($old_mac)} @$data;
            if ($device) {
                $device_id = $device->{mac};
            }
            $c->log->debug("Snom unregister query successful, data: " . $res->decoded_content);
            $data = decode_json($res->decoded_content);
            $url = "$company_url/endpoints/$device_id";
            $ret = {
                method =>'DELETE',
                url => $url,
                body => undef,
                hawk => $self->generate_header($url, "DELETE", { credentials => $credentials, content_type => '', payload => '' }),
            };
        } else {
            $c->log->error("Snom unregister query failed (" . $res->status_line . "): " . $res->decoded_content);
            return;
        }
    }

    return $ret;
}

sub generate_header {
    my ($self, $uri, $method, $options) = @_;

    my $time = time;
    my $credentials = $options->{credentials};

    my @chars = ("A".."Z", "a".."z");
    my $nonce;
    $nonce .= $chars[rand @chars] for 1..8;

    $uri = URI->new($uri);

    my $hash = $self->calculate_payload_hash($options->{payload}, $options->{content_type}, $credentials->{key});

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

1;
