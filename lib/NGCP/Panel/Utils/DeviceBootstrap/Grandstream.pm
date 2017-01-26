package NGCP::Panel::Utils::DeviceBootstrap::Grandstream;

use strict;
use Moose;
use Data::Dumper;
extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';

sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto    => 'https',
        host     => '',
        port     => '',
        path     => '',
    };
    $cfg->{headers} = { %{$self->get_basic_authorization($self->params->{credentials})} };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}

override 'redirect_server_call' => sub {
    my($self,$action) = @_;
    return 1;
};

sub register_content {
    my $self = shift;
    $self->{register_content} = "";
    return $self->{register_content};
}

sub unregister_content {
    my $self = shift;
    $self->{unregister_content} =  "";
    return $self->{unregister_content};
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
