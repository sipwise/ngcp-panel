package NGCP::Panel::Utils::DeviceBootstrap::Yealink;

use strict;
use Moo;
use Types::Standard qw(Str);
use Digest::MD5 qw/md5_hex/;
extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';

has 'register_model_content' => (
    is => 'rw',
    isa => Str,
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

    my $param_servername = $self->content_params->{server_name};
    my $param_mac = $self->content_params->{mac};

    $self->{register_content} ||= <<EOS_XML;
<?xml version='1.0' encoding='UTF-8'?>
<methodCall>
    <methodName>redirect.registerDevice</methodName>
    <params>
        <param>
            <value><string>$param_mac</string></value>
        </param>
        <param>
            <value><string><![CDATA[$param_servername]]></string></value>
        </param>
    </params>
</methodCall>
EOS_XML
    return $self->{register_content};
}

sub unregister_content {
    my $self = shift;

    my $param_macold = $self->content_params->{mac_old} // '';

    $self->{unregister_content} ||=  <<EOS_XML;
<?xml version='1.0' encoding='UTF-8'?>
<methodCall>
    <methodName>redirect.deRegisterDevice</methodName>
    <params>
        <param>
            <value><string>$param_macold</string></value>
        </param>
    </params>
</methodCall>
EOS_XML
    return $self->{unregister_content};
}
sub register_model_content {
    my $self = shift;

    my $param_servername = $self->content_params->{server_name};
    my $param_uri = $self->content_params->{uri};

    $self->{register_model_content} ||=  <<EOS_XML;
<?xml version='1.0' encoding='UTF-8'?>
<methodCall>
    <methodName>redirect.addServer</methodName>
    <params>
        <param>
            <value>
                <string><![CDATA[$param_servername]]></string>
            </value>
        </param>
        <param>
            <value>
                <string><![CDATA[$param_uri]]></string>
            </value>
        </param>
    </params>
</methodCall>
EOS_XML
    return $self->{register_model_content};
}

around 'process_bootstrap_uri' => sub {
    my($orig_method, $self, $uri) = @_;
    $uri = $self->$orig_method($uri);
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
