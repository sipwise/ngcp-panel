package NGCP::Panel::Utils::DeviceBootstrap::SipwiseRedirect;

use strict;
use warnings;

use URI::Escape;
use Data::Dumper;
use Moo;
use Types::Standard qw(Str);
use JSON qw/encode_json decode_json/;

extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorREST';

sub rpc_server_params {
    my $self = shift;
    my $cfg  = {
        proto       => 'http',
        host        => 'localhost',
        port        => '3000',
        path        => '/api',
    };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

sub rest_prepare_request {
    my ($self, $action) = @_;
    my $ret;
	my $new_mac = $self->content_params->{mac};
	my $old_mac = $self->content_params->{mac_old};
	my $redirect_url = $self->get_bootstrap_uri();

    if ($action eq 'register_content') {
        $ret = {
            method =>'POST',
            url => '/devices',
            body => { data => { mac => $new_mac, profile_id => undef, url => $redirect_url} },
        };
    } elsif ($action eq 'unregister_content') {
		my $req = HTTP::Request->new(GET => '/devices?q='.$old_mac);
		my $res = $self->_ua->request($req);
		if ($res->is_success) {
			my $data = decode_json($res->decoded_content);
			my $dev;
			if (ref $data eq 'HASH' && exists $data->{data} && ref $data->{data} eq 'ARRAY' && @{ $data->{data} }) {
				$dev = shift @{ $data->{data} };
			} else {
				return;
			}
			$ret = {
				method =>'DELETE',
				url => '/devices/' . $dev->{id},
				body => undef,
			};
		} else {
			return;
		}
    }


    return $ret;
}

1;

# vim: set tabstop=4 expandtab:
