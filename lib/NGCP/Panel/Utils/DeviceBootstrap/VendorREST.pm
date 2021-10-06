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
    elsif ($data->{hawk}) {
        $req->header(Authorization => $data->{hawk});
        $req->header('accept' => 'application/json');
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

1;

# vim: set tabstop=4 expandtab:
