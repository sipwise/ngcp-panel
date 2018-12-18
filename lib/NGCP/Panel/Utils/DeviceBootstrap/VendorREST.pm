package NGCP::Panel::Utils::DeviceBootstrap::VendorREST;

use strict;
use HTTP::Request;
use JSON qw/encode_json decode_json/;
extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';
use Data::Dumper;

sub redirect_server_call {
    my ($self, $action) = @_;
    my $c = $self->params->{c};
    mu $ret;
    $self->init_content_params();

    my $method = $action.'_content';
	my $data = $self->rest_prepare_request($method);
    return "Failed to perform '$action'" unless $data;

	my $req = HTTP::Request->new($data->{method} => $data->{url});
    if (defined $data->{body}) {
        $req->content(encode_json($data->{body}));
        $req->content_type('application/json');
    }
    my $res = $self->_ua->request($req);
    if ($res->is_success) {
        return "Success";
    } else {
        return "Failed";
    }
}

1;

# vim: set tabstop=4 expandtab:
