package NGCP::Panel::Utils::DeviceBootstrap;

use strict;
use URI::Escape;
use MIME::Base64 qw/encode_base64/;
use Net::HTTPS::Any qw/https_post/;
#use RPC::XML::Parser::LibXML;
#use RPC::XML::Parser::XMLLibXML;
use RPC::XML::ParserFactory 'XML::LibXML';
use RPC::XML;

use Data::Dumper;

sub bootstrap{
    my ($params) = @_;
    my $c = $params->{c};
    my $bootstrap_method = $params->{bootstrap_method};

    $c->log->debug( "bootstrap_method=$bootstrap_method;" );
    my $ret;
    
    if('redirect_panasonic' eq $bootstrap_method){
        $ret = panasonic_bootstrap_register($params);
    }elsif('redirect_linksys' eq $bootstrap_method){
        $ret = linksys_bootstrap_register($params);
    }elsif('http' eq $bootstrap_method){
        #$ret = panasonic_bootstrap_register($params);
    }

    return $ret;
}

sub panasonic_bootstrap_register{
    my ($params) = @_;
    my $c = $params->{c};
    #$params = {
    #    redirect_uri
    #    redirect_uri_params
    #    mac
    #    old_mac (optional)
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
    
    $params->{redirect_uri_params} ||= '{MAC}';
    my $uri = get_bootstrap_uri($params);
    $uri = URI::Escape::uri_escape($uri);
    
    my $mac = $params->{mac};
    $mac =~s/[^A-F0-9]//gi;
    $mac = uc($mac);
    my $old_mac = $params->{old_mac};
    if(defined $old_mac) {
        $old_mac =~s/[^A-F0-9]//gi;
        $old_mac = uc($old_mac);
    }
    
    if(defined $old_mac && $mac ne $old_mac) {
        my $content = "<?xml version=\"1.0\"?> 
<methodCall> 
<methodName>ipredirect.unregisterPhone</methodName> 
<params> 
<param><value><string>".$old_mac."</string></value></param> 
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
        my $response_value = '';
        $c->log->info( "response=$response_code; page=$page;" );
        if($page){
            my $parser = RPC::XML::ParserFactory->new();
            my $rpc_response = $parser->parse($page);
            $response_value = $rpc_response->value->value;
            $c->log->info("unregister response_value=".Dumper($response_value));
        }
    }
    
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
    my $response_value = '';
    $c->log->info( "response=$response_code; page=$page;" );
    if($page){
        my $parser = RPC::XML::ParserFactory->new();
        my $rpc_response = $parser->parse($page);
        $response_value = $rpc_response->value->value;
        $c->log->info( "response_value=".Dumper($response_value).";" );
    }

    my $response;
    if(('HASH' eq ref $response_value) && $response_value->{faultString}){
        return $response_value->{faultString};
    } else {
        return;
    }
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
sub bootstrap_config{
    my($c, $fdev, $old_identifier) = @_;
    
    my $device = $fdev->profile->config->device;

    my $credentials = $fdev->profile->config->device->autoprov_redirect_credentials;
    my $vcredentials;
    if($credentials){
        $vcredentials = { map { $_ => $credentials->$_ } qw/user password/};
    }

    my $sync_params_rs = $device->autoprov_sync->search_rs({
        'autoprov_sync_parameters.parameter_name' => 'sync_params',
    },{
        join   => 'autoprov_sync_parameters',
        select => ['me.parameter_value'],
    });
    my $sync_params = $sync_params_rs->first ? $sync_params_rs->first->parameter_value : '';
    my $ret = NGCP::Panel::Utils::DeviceBootstrap::bootstrap({
        c => $c,
        mac => $fdev->identifier,
        old_mac => $old_identifier,
        bootstrap_method => $device->bootstrap_method,
        redirect_uri_params => $sync_params,
        credentials => $vcredentials,
    });
    return $ret;
}
sub devmod_sync_parameters_prefetch{
    my($c,$devmod,$params) = @_;
    my $schema = $c->model('DB');
    my $bootstrap_method = $params->{'bootstrap_method'};
    my $bootstrap_params_rs = $schema->resultset('autoprov_sync_parameters')->search_rs({
        'me.bootstrap_method' => $bootstrap_method,
    });
    my @parameters = ();
    foreach ($bootstrap_params_rs->all){
        my $sync_parameter = {
            device_id       => $devmod ? $devmod->id : undef,
            parameter_id    => $_->id,
            parameter_value => delete $params->{'bootstrap_config_'.$bootstrap_method.'_'.$_->parameter_name},
        };
        push @parameters,$sync_parameter;
    }
    foreach (keys %$params){
        if($_ =~/^bootstrap_config_/i){
            delete $params->{$_};
        }
    }
    return \@parameters;
}
sub devmod_sync_parameters_store {
    my($c,$devmod,$sync_parameters) = @_;
    my $schema = $c->model('DB');
    foreach my $sync_parameter (@$sync_parameters){
        $sync_parameter->{device_id} ||= $devmod ? $devmod->id : undef
        $schema->resultset('autoprov_sync')->create($sync_parameter);
    }
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
