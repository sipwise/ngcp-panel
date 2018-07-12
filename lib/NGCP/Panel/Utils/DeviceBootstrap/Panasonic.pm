package NGCP::Panel::Utils::DeviceBootstrap::Panasonic;

use strict;
use Moo;
use Data::Dumper;
extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';

sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => 'provisioning.e-connecting.net',
        port     => '443',
        path     => '/redirect/xmlrpc',
        realm    => 'Please Enter Your Password',
    };
    $cfg->{headers} = { %{$self->get_basic_authorization($self->params->{credentials})} };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

sub register_content {
    my $self = shift;
    my $mac_param = $self->content_params->{mac};
    my $uri_param = $self->content_params->{uri};
#<param><value><string>".URI::Escape::uri_escape($self->content_params->{uri})."</string></value></param> 
    $self->{register_content} = <<EOS_XML;
<?xml version="1.0"?>
    <methodCall>
        <methodName>ipredirect.registerPhone</methodName>
        <params>
            <param><value><string>$mac_param</string></value></param>
            <param><value><string><![CDATA[$uri_param]]></string></value></param>
        </params>
    </methodCall>
EOS_XML
    return $self->{register_content};
}

sub unregister_content {
    my $self = shift;
    my $param_macold = $self->content_params->{mac_old} // '';
    $self->{unregister_content} =  <<EOS_XML;
<?xml version="1.0"?>
    <methodCall>
        <methodName>ipredirect.unregisterPhone</methodName>
        <params>
            <param><value><string>$param_macold</string></value></param>
        </params>
    </methodCall>
EOS_XML
    return $self->{unregister_content};
}

around 'process_bootstrap_uri' => sub {
    my($orig_method, $self, $uri) = @_;
    $uri = $self->$orig_method($uri);
    $uri = $self->bootstrap_uri_mac($uri);
    $self->content_params->{uri} = $uri;
    return $self->content_params->{uri};
};

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
