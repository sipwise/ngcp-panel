package NGCP::Panel::Utils::DeviceBootstrap::VendorRPC;

use strict;
use URI::Escape;
use MIME::Base64 qw/encode_base64/;
use LWP::UserAgent;
use HTTP::Request::Common;
use RPC::XML::ParserFactory 'XML::LibXML';
use RPC::XML;
use Data::Dumper;
use Moo;
use Types::Standard qw(HashRef Str);

has 'params' => (
    is => 'rw',
    isa => HashRef,
);
has 'content_params' => (
    is => 'rw',
    isa => HashRef,
);
has 'response' => (
    is => 'rw',
);
has 'rpc_server_params' => (
    is => 'rw',
    isa => HashRef,
    accessor => '_rpc_server_params',
);
has 'register_content' => (
    is => 'rw',
    isa => Str,
    accessor => '_register_content',
);
has 'unregister_content' => (
    is => 'rw',
    isa => Str,
    accessor => '_unregister_content',
);

has '_ua' => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;

        my $c = $self->params->{c};
        my $vendor = lc($self->params->{vendor} // '');
        my ($verify_ssl, $verify_ssl_hostname) = (1,1);
        if ($c && $vendor) {
            
            my $autoprov_config = $c->config->{deviceprovisioning};
            if (ref $autoprov_config eq 'HASH') {
                if ($autoprov_config->{skip_vendor_ssl_verify}) {
                    if (grep {$_ eq $vendor} split(/\W+/, lc($autoprov_config->{skip_vendor_ssl_verify}))) {
                        $verify_ssl = 0;
                    }
                }
                if ($autoprov_config->{skip_vendor_ssl_verify_hostname}) {
                    if (grep {$_ eq $vendor} split(/\W+/, lc($autoprov_config->{skip_vendor_ssl_verify_hostname}))) {
                        $verify_ssl_hostname = 0;
                    }
                }
            }
            $c->log->debug("vendor: $vendor; verify_ssl: $verify_ssl; verify_ssl_hostname: $verify_ssl_hostname;");
        }
        my $ua = LWP::UserAgent->new(keep_alive => 0);
        $ua->ssl_opts(
            SSL_verify_mode => $verify_ssl,
            verify_hostname => $verify_ssl_hostname,
        );
        return $ua;
    }
);

sub redirect_server_call{
    my ($self, $action) = @_;
    my $c = $self->params->{c};
    $self->init_content_params();
    my($content,$response_value,$ret);
    my $method = $action.'_content';
    if($self->can($method)){
        $content = $self->$method();
    }else{
        $ret = "Unknown method: $action";
    }
    if($content){
        $response_value = $self->rpc_https_call($content);
        $ret = $self->extract_response_description($response_value);
    }
    return $ret;
}

sub rpc_https_call{
    my($self, $content, $cfg) = @_;
    $cfg //= $self->rpc_server_params;
    my $c = $self->params->{c};
    $cfg->{query_string} //= '';
    $c->log->debug( "rpc_https_call: host=$cfg->{host}; port=$cfg->{port}; path=$cfg->{path}; query_string=$cfg->{query_string}; content=$content;" );
    #$c->log->debug( Dumper($cfg->{headers}) );
    my( $page, $response_code, $response_value, $reply_headers ) = ('','','',{});
    eval {
        local $SIG{ALRM} = sub { die "Connection timeout\n" };
        alarm(25);
        my $ua = $self->_ua;
        $cfg->{port} //= '';
        my $uri = $cfg->{proto}.'://'.$cfg->{host}.($cfg->{port} ? ':' : '').$cfg->{port}.$cfg->{path};
        my $request = POST $uri,
            Content_Type => $cfg->{content_type} // 'text/xml',
            %{$cfg->{headers}},
            Content => $content;
        my $response = $ua->request($request);
        $self->response($response);
        ( $page, $response_code, $reply_headers ) = ($response->content,$response->code,$response->headers);
        alarm(0);
    };
    alarm(0);
    if ($@ && !$page) {
        $c->log->debug( "eval error: $@;" );
        if ($@ =~ /Connection timeout/) {
            $response_value = 'Connection timeout';
        }
    }
    $c->log->info( "response=$response_code; page=$page;" );
    if($page){
        my $rpc_response = $self->parse_rpc_response_page($page);
        $response_value = $self->parse_rpc_response($rpc_response);
    }
    return $response_value;
}

sub parse_rpc_response_page{
    my($self, $page) = @_;
    my $parser = RPC::XML::ParserFactory->new();
    return $parser->parse($page);
}

sub parse_rpc_response{
    my($self,$rpc_response) = @_;
    return $rpc_response->value->value;
}

sub extract_response_description{
    my($self,$response_value) = @_;

    #polyycom version
    if(('HASH' eq ref $response_value) && $response_value->{faultString}){
        return $response_value->{faultString};
    } else {
        return '';
    }
}

sub init_content_params{
    my($self) = @_;
    $self->{content_params} ||= {};
    $self->content_params->{uri} = $self->get_bootstrap_uri();

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
    return { 'Authorization' => 'Basic '.$authorization };
}

sub get_config_uri{
    my ($self) = @_;
    my $uri = $self->params->{redirect_uri};
    my $uri_params = $self->params->{redirect_params}->{sync_params} || '';
    if(!$uri){
        my $cfg = $self->config_uri_conf();
        $uri = "$cfg->{schema}://$cfg->{host}:$cfg->{port}/device/autoprov/config/";
    }
    $uri .= $uri_params;
    return $self->process_bootstrap_uri($uri);
}

sub get_bootstrap_uri{
    my ($self) = @_;
    my $uri = $self->params->{redirect_uri};
    my $uri_params = $self->params->{redirect_params}->{sync_params} || '';
    if(!$uri){
        my $cfg = $self->bootstrap_uri_conf();
        $uri = "$cfg->{schema}://$cfg->{host}:$cfg->{port}/device/autoprov/bootstrap/";
    }
    $uri .= $uri_params;
    return $self->process_bootstrap_uri($uri);
}

sub process_bootstrap_uri{
    my($self,$uri) = @_;
    $uri = $self->bootstrap_uri_protocol($uri);
    return $uri;
}

sub bootstrap_uri_protocol{
    my($self,$uri) = @_;
    if($uri !~/^(?:https?|t?ftp):\/\//i ){
        $uri = 'http://'.$uri;
    }
    return $uri;
}
sub bootstrap_uri_mac{
    my($self, $uri) = @_;
    if ($uri !~/\{MAC\}$/){
        if ($uri !~/\/$/){
            $uri .= '/' ;
        }
        $uri .= '{MAC}' ;
    }
    return $uri;
}

#separated as this logic also used in other places, so can be moved to other utils module
sub bootstrap_uri_conf{
    my ($self) = @_;
    my $c = $self->params->{c};
    my $cfg = {
        #schema => $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http',
        schema => 'http', # for bootstrapping, we always use http
        host => $c->config->{deviceprovisioning}->{host} // $c->req->uri->host,
        port => $c->config->{deviceprovisioning}->{bootstrap_port} // 1445,
    };
    return $cfg;
}

sub config_uri_conf{
    my ($self) = @_;
    my $c = $self->params->{c};
    my $cfg = {
        schema => $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http',
        host => $c->config->{deviceprovisioning}->{host} // $c->req->uri->host,
        port => $c->config->{deviceprovisioning}->{port} // 1444,
    };
    return $cfg;
}

sub unknown_error{
    my ($self) = @_;
    my $c = $self->params->{c};
    return $c->loc('Unknown error');
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
