package NGCP::Panel::Utils::DeviceBootstrap::Polycom;

use strict;
use Moose;
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
has 'add_server_content' => (
    is => 'rw',
    isa => 'Str',
    accessor => '_add_server_content',
);
sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => 'ztpconsole.polycom.com',
        port     => '443',
        path     => '/inboundservlet/GenericServlet',
        login    => '',
        password => '',
        profile  => 'sipwise',
        #https://ztpconsole.polycom.com/inboundservlet/GenericServlet
    };
    $cfg->{headers} = { %{$self->get_basic_authorization($self->params->{credentials})} };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

sub register_content {
    my $self = shift;
    $self->{register_content} ||= "<?xml version='1.0' encoding='UTF-8'?>
<request userid='".$self->{rpc_server_params}->{login}."' password='".$self->{rpc_server_params}->{password}."' message-id='1001' >
<create-subscriber account-id = '".$self->content_params->{mac}."' isp-name= '".$self->{rpc_server_params}->{profile}."'>
</create-subscriber>
</request>";
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
sub add_subscriber_content
 {
    my $self = shift;
    $self->{add_subscriber_content} ||=  "<?xml version='1.0' encoding='UTF-8'?>
<request userid='".$self->{rpc_server_params}->{login}."' password='".$self->{rpc_server_params}->{password}."' message-id='1001' >
<create-subscriber account-id = '".$self->content_params->{mac}."' isp-name= '".$self->{rpc_server_params}->{profile}."'>
</create-subscriber>
</request>";
    return $self->{add_subscriber_content};
}
sub register{
    my($self) = @_;
    $self->rpc_server_params;
    #$self->redirect_server_call('add_subscriber');
    #return $self->redirect_server_call('register');
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
