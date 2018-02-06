package NGCP::Panel::Utils::DeviceBootstrap::Snom;

use strict;
use Moo;
use Data::Dumper;
extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';

sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => 'provisioning.snom.com',
        port     => '8083',
        path     => '/xmlrpc',
    };
    $cfg->{headers} = { %{$self->get_basic_authorization($self->params->{credentials})} };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

sub register_content {
    my $self = shift;
#<param><value><string>".URI::Escape::uri_escape($self->content_params->{uri})."</string></value></param> 
#http://fox.snom.com/prv2.php?mac={mac}
    $self->{register_content} = "<?xml version='1.0'?>
<methodCall>
 <methodName>redirect.registerPhone</methodName>
 <params>
  <param>
   <value><string>".$self->content_params->{mac}."</string></value>
  </param>
  <param>
   <value><string>".$self->content_params->{uri}."</string></value>
  </param>
 </params>
</methodCall>";
    return $self->{register_content};
}

sub unregister_content {
    my $self = shift;
    $self->{unregister_content} =  "<?xml version='1.0'?>
<methodCall>
 <methodName>redirect.deregisterPhone</methodName>
 <params>
  <param>
   <value><string>".($self->content_params->{mac_old} // '')."</string></value>
  </param>
 </params>
</methodCall>";
    return $self->{unregister_content};
}
around 'extract_response_description' => sub {
    my($orig_method, $self, $rpc_value) = @_;
    my $c = $self->params->{c};
    my $res = '';

    if(ref $rpc_value eq 'ARRAY'){
        #1 - success; 0 - error, error string is a second param
        if($rpc_value->[0] eq '1'){
            $res = '';#clear the error
        }elsif($rpc_value->[0] eq '0'){
            return $rpc_value->[1];
        }else{
            $res = $self->unknown_error;
        }
    }else{
        $res = $self->unknown_error;
    }
    return $res;
};

around 'process_bootstrap_uri' => sub {
    my($orig_method, $self, $uri) = @_;
    $uri = $self->$orig_method($uri);
    $uri = $self->bootstrap_uri_mac($uri);
    $self->content_params->{uri} = $uri;
    return $self->content_params->{uri};
};

around 'bootstrap_uri_mac' => sub {
    my($orig_method, $self, $uri) = @_;
    if ($uri !~/\{mac\}$/){
        if ($uri !~/\/$/){
            $uri .= '/' ;
        }
        $uri .= '?mac={mac}' ;
    }
    return $uri;
};
1;

=head1 NAME

NGCP::Panel::Utils::DeviceBootstrap

=head1 DESCRIPTION

Make API requests to configure remote redirect servers for requested MAC with autorpov uri.
See http://wiki.snom.com/Category:HowTo:XMLRPC_Redirection.

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
