package NGCP::Panel::Utils::DeviceBootstrap::Grandstream;

use strict;
use Moose;
use Data::Dumper;

use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;
use IPC::Run3;

extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';

sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto        => 'https',
        host         => 'fm.grandstream.com',
        port         => '443',
        path         => '/api/provision',
        content_type => 'application/json',
        query_string => '',
        #query_string => $self->{rpc_server_params}->{query_string} // '',
    };
    $cfg->{headers} = {};
    #don't rewrite server params - every time we will set query_string
    $self->{rpc_server_params} //= $cfg;
    return $self->{rpc_server_params};
}

sub register_content {
    my $self = shift;
    #TODO: remove actual cid here
    $self->{register_content} = 
        '{"cid":"'.$self->params->{redirect_params}->{cid}
        .'","method":"redirectDefault","params":{"macs":["'
        .$self->content_params->{mac}.'"]}}';

    my ($sign,$time) = $self->get_request_sign($self->{register_content});
    $self->{rpc_server_params}->{query_string} = '?sig='.$sign.'&time='.$time;
    return $self->{register_content};
}

sub unregister_content {   
    my $self = shift;
    $self->{unregister_content} =
        '{"cid":"'.$self->params->{redirect_params}->{cid}
        .'","method":"unDeviceProvision","params":{"macs":["'
        .$self->content_params->{mac}.'"]}}';

    my ($sign,$time) = $self->get_request_sign($self->{unregister_content});
    $self->{rpc_server_params}->{query_string} = '?sig='.$sign.'&time='.$time;
    return $self->{unregister_content};
}

override 'parse_rpc_response_page' => sub {
    my($self, $page) = @_;
    my $res = JSON::from_json($page);
    return $res;
};

override 'parse_rpc_response' => sub {
    my($self,$rpc_response) = @_;
    return $rpc_response;
};

#Todo: unify it with snome and vendor version somehow and move to VendorRPC.pm
override 'extract_response_description' => sub {
    my($self,$rpc_value) = @_;
    my $res = '';

    if(ref $rpc_value eq 'HASH'){
        #0 - success; > 0 - different errors. See p. 16 of the GAPS_API_Guide.pdf
        if($rpc_value->{code} eq '0'){
            $res = '';#clear the error
        }elsif($rpc_value->{code} > 0){
            return $rpc_value->{desc};
        }else{
            $res = $self->unknown_error;
        }
    }else{
        $res = $self->unknown_error;
    }
    return $res;
};


sub get_server_time {
    my $self = shift;
    my $ua = LWP::UserAgent->new;
    my $req = HTTP::Request->new('GET', 
        $self->rpc_server_params->{proto}
        .'://'.$self->rpc_server_params->{host}
        .$self->rpc_server_params->{path});

    my $time_response = $ua->request($req);
    my $time_content = JSON::from_json($time_response->decoded_content);
    return $time_content->{time};
}

sub get_request_sign{
    my $self = shift;
    my ($request,$time) = @_;
    my $key = $self->params->{redirect_params}->{key};
    $time //= $self->get_server_time();
    my $str2sign = $request.$time;
    my ($sign,$sign_error);
    my $cmd = "openssl sha1 -hmac '$key' -binary|xxd -p";
    #sig=$(echo -n $str2sign | openssl sha1 -hmac $key -binary|xxd -p)
    #run3 \@cmd, \$in, \$out, \$err;
    run3 $cmd, \$str2sign, \$sign, \$sign_error;
    $sign=~s/\n//g;
    return ($sign, $time);
}
1;

=head1 NAME

NGCP::Panel::Utils::DeviceBootstrap

=head1 DESCRIPTION

Make API requests to configure remote redirect servers for requested MAC with autorpov uri.

=head1 METHODS

=head2 bootstrap

Dispatch to proper vendor API call.

=head1 AUTHOR

Irina Peshinskaya C<< <ipeshinskaya@sipwise.com> >>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
# vim: set tabstop=4 expandtab:
