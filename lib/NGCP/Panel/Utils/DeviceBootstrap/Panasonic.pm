package NGCP::Panel::Utils::DeviceBootstrap::Panasonic;

use strict;
use Moose;
use Data::Dumper;
extends 'NGCP::Panel::Utils::DeviceBootstrap::RPC';

has 'rpc_server_params' => (
    is => 'rw',
    isa => 'HashRef',
    accessor => '_rpc_server_params',
);
has 'register_content' => (
    is => 'rw',
    isa => 'Str',
    accessor => '_register_content',
);
has 'unregister_content' => (
    is => 'rw',
    isa => 'Str',
    accessor => '_unregister_content',
);
sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => 'provisioning.e-connecting.net',
        port     => '443',
        path     => '/redirect/xmlrpc',
    };
    $cfg->{headers} = { %{$self->get_basic_authorization($self->params->{credentials})} };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

sub register_content {
    my $self = shift;
    $self->{register_content} = "<?xml version=\"1.0\"?> 
<methodCall> 
<methodName>ipredirect.registerPhone</methodName> 
<params> 
<param><value><string>".$self->content_params->{mac}."</string></value></param> 
<param><value><string>".$self->content_params->{uri}."</string></value></param> 
</params> 
</methodCall>";
    return $self->{register_content};
}

sub unregister_content {
    my $self = shift;
    $self->{unregister_content} =  "<?xml version=\"1.0\"?> 
<methodCall> 
<methodName>ipredirect.unregisterPhone</methodName> 
<params> 
<param><value><string>".$self->content_params->{mac_old}."</string></value></param> 
</params> 
</methodCall>";
    return $self->{unregister_content};
}

sub parse_rpc_response{
    my($self,$rpc_response) = @_;
    return $rpc_response->value->value;
}

sub extract_response_description{
    my($self,$response_value) = @_;

    if(('HASH' eq ref $response_value) && $response_value->{faultString}){
        return $response_value->{faultString};
    } else {
        return;
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
