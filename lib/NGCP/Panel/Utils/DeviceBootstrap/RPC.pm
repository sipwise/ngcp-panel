package NGCP::Panel::Utils::DeviceBootstrap::RPC;

use strict;
use URI::Escape;
use MIME::Base64 qw/encode_base64/;
use Net::HTTPS::Any qw/https_post/;
use RPC::XML::ParserFactory 'XML::LibXML';
use RPC::XML;
use Data::Dumper;
use Moose;

has 'params' => (
    is => 'rw',
    isa => 'HashRef',
);
has 'content_params' => (
    is => 'rw',
    isa => 'HashRef',
);
has 'rpc_server_params' => (
    is => 'rw',
    isa => 'HashRef',
);

sub redirect_register{
    my ($self) = @_;
    my $c = $self->params->{c};
    $self->init_content_params();
    $c->log->debug(Dumper ($self->content_params));
    my($content,$response_value);
    if(defined $self->content_params->{mac_old} && $self->content_params->{mac} ne $self->content_params->{mac_old}) {
        $content = $self->unregister_content();
        $response_value = $self->rpc_https_call($content);
    }
    $content = $self->register_content();
    $response_value = $self->rpc_https_call($content);
    return $self->extract_response_description($response_value);
}

sub rpc_https_call{
    my($self, $content, $cfg) = @_;
    $cfg //= $self->rpc_server_params;
    my $c = $self->params->{c};
    $c->log->debug( "host=$cfg->{host}; port=$cfg->{port}; path=$cfg->{path}; content=$content;" );
    my( $page, $response_code, %reply_headers ) = https_post({
        'host'    => $cfg->{host},
        'port'    => $cfg->{port},
        'path'    => $cfg->{path},
        'headers' => $cfg->{headers},
        'Content-Type' => 'text/xml',
        'content' => $content,
    },);
    $c->log->info( "response=$response_code; page=$page;" );
    my $response_value = '';
    if($page){
        my $parser = RPC::XML::ParserFactory->new();
        my $rpc_response = $parser->parse($page);
        $response_value = $self->parse_rpc_response($rpc_response);
        $c->log->info("response_value=".Dumper($response_value));
    }
    return $response_value;
}
sub init_content_params{
    my($self) = @_;
    $self->params->{redirect_uri_params} ||= '{MAC}';
    my $uri = $self->get_bootstrap_uri();
    $self->{content_params} ||= {};
    $self->content_params->{uri} = URI::Escape::uri_escape($uri);
    $self->content_params->{mac} = normalize_mac($self->params->{mac});
    if(defined $self->params->{mac_old}) {
        $self->content_params->{mac_old} = normalize_mac($self->params->{mac_old});
    }
}
sub normalize_mac {
    my ($mac) = @_;
    return unless($mac);
    $mac =~s/[^A-F0-9]//gi;
    $mac = uc($mac);
    return $mac;
}
sub get_basic_authorization{
    my($self) = @_;
    my $authorization = encode_base64(join(':',@{$self->params->{credentials}}{qw/user password/}));
    $authorization =~s/[ \s]//gis;
    $authorization .= '=';
    return { 'Authorization' => 'Basic '.$authorization };
}
sub get_bootstrap_uri{
    my ($self) = @_;
    my $uri = $self->params->{redirect_uri};
    my $uri_params = $self->params->{redirect_uri_params} || '';
    if($uri){
        if(!$uri =~/^https?:\/\//i ){
            $uri = 'http://'.$uri;
        }
    }else{
        my $cfg = $self->get_bootstrap_uri_conf();
        $uri = "$cfg->{schema}://$cfg->{host}:$cfg->{port}/device/autoprov/config/";
    }
    $uri .= $uri_params;
    return $uri;
}
sub get_bootstrap_uri_conf{
    my ($self) = @_;
    my $c = $self->params->{c};
    my $cfg = {
        schema => $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http',
        host => $c->config->{deviceprovisioning}->{host} // $c->req->uri->host,
        port => $c->config->{deviceprovisioning}->{port} // 1444,
    };
    return $cfg;
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
