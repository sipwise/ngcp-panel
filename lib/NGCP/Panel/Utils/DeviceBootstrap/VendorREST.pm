package NGCP::Panel::Utils::DeviceBootstrap::VendorREST;

use strict;
use warnings;

use Moo;
use HTTP::Request;
use JSON qw/encode_json decode_json/;
extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';

sub redirect_server_call {
    my ($self, $action) = @_;
    my $c = $self->params->{c};
    $self->init_content_params();

    $c->log->debug("Performing VendorREST call for action '$action'");

    my $method = $action.'_content';
    my $data = $self->rest_prepare_request($method);
    unless ($data) {
        $c->log->debug("VendorREST call for action '$action' failed due to missing data");
        return "No bootstrap data from redirect service";
    }

    my $req = HTTP::Request->new($data->{method} => $data->{url});
    if ($data->{token}) {
        $req->header(token => $data->{token});
    }
    else {
        $req->header(%{$self->get_basic_authorization($self->params->{credentials})});
    }
    if (defined $data->{body}) {
        $req->content(encode_json($data->{body}));
        $req->content_type('application/json');
    }
    my $res = $self->_ua->request($req);
    if ($res->is_success) {
        $c->log->info("Performing VendorREST for action '$action' succeeded");
        return 0;
    } else {
        $c->log->error("Performing VendorREST for action '$action' failed (" . $res->status_line . "): " . $res->decoded_content);
        return "Failed to perform redirect service action";
    }
}

1;

# vim: set tabstop=4 expandtab:
