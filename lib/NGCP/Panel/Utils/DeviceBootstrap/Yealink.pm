package NGCP::Panel::Utils::DeviceBootstrap::Yealink;

use strict;
use Moose;
use Digest::MD5 qw/md5_hex/;
extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';

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
has 'register_model_content' => (
    is => 'rw',
    isa => 'Str',
    accessor => '_register_model_content',
);
sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => 'rps.yealink.com',
        port     => '443',
        path     => '/xmlrpc',
    };
    $cfg->{headers} = { %{$self->get_basic_authorization($self->params->{credentials})} };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

sub register_content {
    my $self = shift;
    $self->{register_content} ||= "<?xml version='1.0' encoding='UTF-8'?>
<methodCall>
<methodName>redirect.registerDevice</methodName>
<params>
<param>
<value><string>".$self->content_params->{mac}."</string></value>
</param>
<param>
<value><string><![CDATA[".$self->content_params->{server_name}."]]></string></value>
</param>
</params>
</methodCall>";
    return $self->{register_content};
}

sub unregister_content {
    my $self = shift;
    $self->{unregister_content} ||=  "<?xml version='1.0' encoding='UTF-8'?>
<methodCall>
<methodName>redirect.deRegisterDevice</methodName>
<params>
<param>
<value><string>".$self->content_params->{mac_old}."</string></value>
</param>
</params>
</methodCall>";
    return $self->{unregister_content};
}
sub register_model_content {
    my $self = shift;
    $self->{register_model_content} ||=  "<?xml version='1.0' encoding='UTF-8'?>
<methodCall>
<methodName>redirect.addServer</methodName>
<params>
<param>
<value>
<string><![CDATA[".$self->content_params->{server_name}."]]></string>
</value>
</param>
<param>
<value>
<string><![CDATA[".$self->content_params->{uri}."]]></string>
</value>
</param>
</params>
</methodCall>";
    return $self->{register_model_content};
}

override 'process_bootstrap_uri' => sub {
    my($self,$uri) = @_;
    $uri = super($uri);
    $self->content_params->{uri} = $uri;
    $self->bootstrap_uri_server_name($uri);
    return $self->content_params->{uri};
};

sub bootstrap_uri_server_name{
    my($self,$uri) = @_;
    $uri ||= $self->content_params->{uri};
    #http://stackoverflow.com/questions/4826403/hash-algorithm-with-alphanumeric-output-of-20-characters-max
    $self->content_params->{server_name} ||= substr(md5_hex($uri),0,20);
    return $self->content_params->{server_name};
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
