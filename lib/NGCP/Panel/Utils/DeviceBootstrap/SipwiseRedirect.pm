package NGCP::Panel::Utils::DeviceBootstrap::SipwiseRedirect;

use strict;
use warnings;

use URI::Escape;
use Moo;
use Types::Standard qw(Str);
use JSON qw/encode_json decode_json/;

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
        $ret = {
            method =>'POST',
            url => "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/devices",
            body => { data => { mac => $new_mac, profile_id => undef, url => $redirect_url} },
        };
    } elsif ($action eq 'unregister_content') {
        # we've to fetch the id first before constructing the delete request
        my $url = "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/devices?q=$old_mac";
        $c->log->debug("SipwiseRedirect unregister via url '$url'");
		my $req = HTTP::Request->new(GET => $url);
        $req->header(%{$self->get_basic_authorization($self->params->{credentials})});
		my $res = $self->_ua->request($req);
		if ($res->is_success) {
            $c->log->debug("SipwiseRedirect unregister query successful, data: " . $res->decoded_content);
			my $data = decode_json($res->decoded_content);
			my $dev;
			if (ref $data eq 'HASH' && exists $data->{data} && ref $data->{data} eq 'ARRAY' && @{ $data->{data} }) {
				$dev = shift @{ $data->{data} };
			} else {
                $c->log->error("SipwiseRedirect unregister query failed due to invalid body");
				return;
			}
			$ret = {
				method =>'DELETE',
                url => "$$cfg{proto}://$$cfg{host}:$$cfg{port}/$$cfg{path}/devices/$$dev{id}",
				body => undef,
			};
		} else {
            $c->log->error("SipwiseRedirect unregister query failed (" . $res->status_line . "): " . $res->decoded_content);
			return;
		}
    }


    return $ret;
}

1;

# vim: set tabstop=4 expandtab:
