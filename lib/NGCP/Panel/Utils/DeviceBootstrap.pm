package NGCP::Panel::Utils::DeviceBootstrap;

use strict;
use URI::Escape;
use MIME::Base64 qw/encode_base64/;
use Net::HTTPS::Any qw/https_post/;
use RPC::XML::Parser::LibXML;
use Data::Dumper;

sub bootstrap_config{
    my($c, $fdev, $contract) = @_;

    my $err = 0;
    my $device = $fdev->profile->config->device;

    if(!$contract){
        $contract = $c->stash->{contract};
    }
    my $credentials = $contract->vendor_credentials->search_rs({
        'me.vendor' => lc($device->vendor),
    })->first;
    if($credentials){
        my $vendor_credentials = { map { $_ => $credentials->$_ } qw/user password/};

        my $sync_params_rs = $device->autoprov_sync->search_rs({
            'autoprov_sync_parameters.parameter_name' => 'sync_params',
        },{
            join   => 'autoprov_sync_parameters',
            select => ['me.parameter_value'],
        });
        my $sync_params = $sync_params_rs->first ? $sync_params_rs->first->parameter_value : '';
        NGCP::Panel::Utils::DeviceBootstrap::bootstrap({
            c => $c,
            mac => $fdev->identifier,
            bootstrap_method => $device->bootstrap_method,
            redirect_uri_params => $sync_params,
            credentials => $vendor_credentials,
        });
    }else{
        $err = 1;
    }
    return $err;
}

sub bootstrap{
    my ($params) = @_;
    my $c = $params->{c};
    my $bootstrap_method = $params->{bootstrap_method};

    $c->log->debug( "bootstrap_method=$bootstrap_method;" );
    
    if('redirect_panasonic' == $bootstrap_method){
        panasonic_bootstrap_register($params);
    }elsif('redirect_linksys' == $bootstrap_method){
        linksys_bootstrap_register($params);
    }elsif('http' == $bootstrap_method){
        panasonic_bootstrap_register($params);
    }
}

sub panasonic_bootstrap_register{
    my ($params) = @_;
    my $c = $params->{c};
    #$params = {
    #    redirect_uri
    #    redirect_uri_params
    #    mac
    #    c for log, config sync uri from config
    #    credentials => {user=>, password=>}
    #};
    
    my $cfg  = {
        proto    => 'https',
        host     => 'provisioning.e-connecting.net',
        port     => '443',
        path     => '/redirect/xmlrpc',
    };

    my $authorization = encode_base64(join(':',@{$params->{credentials}}{qw/user password/}));
    $authorization =~s/[ \s]//gis;
    $authorization .= '=';
    
    #params => c,redirect_uri,redirect_uri_params, mac
    #$params->{redirect_uri_params} ||= $params->{mac};
    $params->{redirect_uri_params} ||= '{MAC}';
    my $uri = get_bootstrap_uri($params);
    $uri = URI::Escape::uri_escape($uri);
    
    my $mac = $params->{mac};
    $mac =~s/[^A-F0-9]//gi;
    $mac = uc($mac);
    
    $mac = '0080f0d4dbf1';
    $mac = 'AAAAAAAAAAAA';
    
    my $content = "<?xml version=\"1.0\"?> 
<methodCall> 
<methodName>ipredirect.registerPhone</methodName> 
<params> 
<param><value><string>".$mac."</string></value></param> 
<param><value><string>".$uri."</string></value></param> 
</params> 
</methodCall>";
    $c->log->info( "host=$cfg->{host}; port=$cfg->{port}; path=$cfg->{path}; content=$content;" );
    my( $page, $response_code, %reply_headers ) = https_post({
        'host'    => $cfg->{host},
        'port'    => $cfg->{port},
        'path'    => $cfg->{path},
        'headers' => { 'Authorization' => 'Basic '.$authorization },
        'Content-Type' => 'text/xml',
        'content' => $content,
    },);
    $c->log->info( "response=$response_code; page=$page;" );
    my $rpc_response = parse_rpc_xml($page);
    my $response_value = $rpc_response->value->value;
    $c->log->info( "response_value=".Dumper($response_value).";" );
    my $response;
    if('1' eq $response_value){
        $response = { 'response' => 1 };
    }elsif(('HASH' eq ref $response_value) && $response_value->{faultCode}){
        $response = $response_value;
        $response->{response} = 0;
    }
    $c->log->debug( "response=".Dumper($response).";" );
    return $response;
}
sub get_bootstrap_conf{
    my ($params) = @_;
    my $c = $params->{c};
    my $cfg = {
        schema => $c->config->{deviceprovisioning}->{secure} ? 'https' : 'http',
        host => $c->config->{deviceprovisioning}->{host} // $c->req->uri->host,
        port => $c->config->{deviceprovisioning}->{port} // 1444,
    };
    return $cfg;
}

sub get_bootstrap_uri{
    my ($params) = @_;
    my $uri = $params->{redirect_uri};
    my $uri_params = $params->{redirect_uri_params} || '';
    if($uri){
        if(!$uri =~/^https?:\/\//i ){
            $uri = 'http://'.$uri;
        }
    }else{
        my $cfg = get_bootstrap_conf($params);
        $uri = "$cfg->{schema}://$cfg->{host}:$cfg->{port}/device/autoprov/config/";
    }
    $uri .= $uri_params;
    return $uri;
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
