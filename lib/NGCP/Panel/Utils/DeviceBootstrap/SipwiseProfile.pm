package NGCP::Panel::Utils::DeviceBootstrap::SipwiseProfile;

use strict;
use warnings;

use URI::Escape;
use Moo;
use Types::Standard qw(Str);
use JSON qw/encode_json decode_json/;
use MIME::Base64;

extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorREST';

sub rpc_server_params {
    my $self = shift;
    my $cfg  = {
        proto       => 'https',
        host        => 'api.eds.sipwise.com',
        port        => '443',
        path        => 'api',
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
    my $redirect_url = $self->get_bootstrap_uri();

    $self->{rpc_server_params} //= $self->rpc_server_params;
    my $cfg = $self->{rpc_server_params};

    if ($action eq 'register_content') {

        # first, fetch profile from eds
        my $url = "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/profiles?q=ngcp";
        $c->log->debug("SipwiseProfile check profile '$url'");
        my $req = HTTP::Request->new(GET => $url);
        $req->header(%{$self->get_basic_authorization($self->params->{credentials})});
        my $res = $self->_ua->request($req);
        my $prof;

        if ($res->is_success) {
            $c->log->debug("SipwiseProfile check profile query successful, data: " . $res->decoded_content);
            my $data = decode_json($res->decoded_content);
            if (ref $data eq 'HASH' && exists $data->{data} && ref $data->{data} eq 'ARRAY' && @{ $data->{data} }) {
                # profile exists, nothing to do
                $prof = shift @{ $data->{data} };
            } elsif (ref $data eq 'HASH' && exists $data->{data} && ref $data->{data} eq 'ARRAY' && @{ $data->{data} } == 0) {
                # profile does not exist, create it
                $c->log->debug("SipwiseProfile ngcp profile not available for this reseller, create it");

                # first we need to create the blob containing the
                # server's ca cert
                my $cacert = encode_base64($c->model('CA')->get_server_ca_cert());
                $url = "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/blobs";
                $c->log->debug("SipwiseProfile create blob '$url'");
                my $req = HTTP::Request->new(POST => $url);
                $req->header(%{$self->get_basic_authorization($self->params->{credentials})});
                $req->content(encode_json({ data => { name => 'ngcp-ca-cert.pem', b64body => $cacert, content_type => 'application/octet-stream' } }));
                $req->content_type('application/json');
                $res = $self->_ua->request($req);
                if ($res->is_success) {
                    $c->log->debug("SipwiseProfile create blob query successful");
                } else {
                    $c->log->error("SipwiseProfile create blob query failed (" . $res->status_line . "): " . $res->decoded_content);
                    return;
                }

                # now create the profile, referring to the blob and the
                # server's provisioning url
                my $profile_body = "<settings><setting override=\"true\" value=\"https:\/\/dev.eds.sipwise.com\/dev\/blob\/\$EDS{MAC}\/ngcp-ca-cert.pem\" id=\"ThirdPartyCAUrl\"\/><setting override=\"true\" value=\"$redirect_url\" id=\"EdsEnetcfgDmUrl\"\/><\/settings>";

                $url = "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/profiles";
                $c->log->debug("SipwiseProfile create profile '$url'");
                my $req = HTTP::Request->new(POST => $url);
                $req->header(%{$self->get_basic_authorization($self->params->{credentials})});
                $req->content(encode_json({ data => { body => $profile_body, content_type => 'text/xml', description => 'ngcp' } }));
                $req->content_type('application/json');
                $res = $self->_ua->request($req);
                if ($res->is_success) {
                    $c->log->debug("SipwiseProfile create profile query successful, data: " . $res->decoded_content);
                    $data = decode_json($res->decoded_content);
                    if (ref $data eq 'HASH' && exists $data->{data} && ref $data->{data} eq 'HASH') {
                        $prof = $data->{data};
                    } else {
                        $c->log->error("SipwiseProfile create profile query failed with invalid data: " . $res->decoded_content);
                        return;
                    }
                } else {
                    $c->log->error("SipwiseProfile create profile query failed (" . $res->status_line . "): " . $res->decoded_content);
                    return;
                }
            } else {
                $c->log->error("SipwiseProfile check profile query failed due to invalid body");
                return;
            }
            $ret = {
                method =>'POST',
                url => "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/devices",
                body => { data => { mac => $new_mac, profile_id => $prof->{id}, url => undef} },
            };
        } else {
            $c->log->error("SipwiseProfile unregister query failed (" . $res->status_line . "): " . $res->decoded_content);
            return;
        }
    } elsif ($action eq 'unregister_content') {
        # we've to fetch the id first before constructing the delete request
        my $url = "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/devices?q=$old_mac";
        $c->log->debug("SipwiseProfile unregister via url '$url'");
        my $req = HTTP::Request->new(GET => $url);
        $req->header(%{$self->get_basic_authorization($self->params->{credentials})});
        my $res = $self->_ua->request($req);
        if ($res->is_success) {
            $c->log->debug("SipwiseProfile unregister query successful, data: " . $res->decoded_content);
            my $data = decode_json($res->decoded_content);
            my $dev;
            if (ref $data eq 'HASH' && exists $data->{data} && ref $data->{data} eq 'ARRAY' && @{ $data->{data} }) {
                $dev = shift @{ $data->{data} };
            } else {
                $c->log->error("SipwiseProfile unregister query failed due to invalid body");
                return;
            }
            $ret = {
                method =>'DELETE',
                url => "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/devices/$$dev{id}",
                body => undef,
            };
        } else {
            $c->log->error("SipwiseProfile unregister query failed (" . $res->status_line . "): " . $res->decoded_content);
            return;
        }
    }


    return $ret;
}

1;

# vim: set tabstop=4 expandtab:
