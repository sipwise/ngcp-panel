package NGCP::Panel::Utils::DeviceBootstrap::Polycom;

use strict;
use URI::Escape;
use XML::Mini::Document;;
use Data::Dumper;
use Moose;

extends 'NGCP::Panel::Utils::DeviceBootstrap::VendorRPC';

has 'register_subscriber_content' => (
    is => 'rw',
    isa => 'Str',
    accessor => '_register_subscriber_content',
);
sub rpc_server_params{
    my $self = shift;
    my $cfg  = {
        proto       => 'https',
        host        => 'ztpconsole.polycom.com',
        port        => '443',
        path        => '/inboundservlet/GenericServlet',
        #https://ztpconsole.polycom.com/inboundservlet/GenericServlet
    };
    #$cfg->{headers} = { %{$self->get_basic_authorization($self->params->{credentials})} };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}
sub register_model{
    my($self) = @_;
    $self->rpc_server_params;
    $self->redirect_server_call('register_package');
}
sub register_package_content {
    my $self = shift;
    #.'_'.$self->content_params->{mac}
    $self->{register_package_content} ||= "<?xml version='1.0' encoding='UTF-8'?>
<request userid='".$self->params->{credentials}->{user}."' password='".$self->params->{credentials}->{password}."' message-id='1001'>
<add-package account-id='".uri_escape($self->params->{redirect_params}->{profile})."'>
<package-data>
<base-package-name>default</base-package-name>
</package-data>
</add-package>
</request>";
    return $self->{register_package_content};
}
sub register_content {
    my $self = shift;
    #.'_'.$self->content_params->{mac}
    $self->{register_content} ||= "<?xml version='1.0' encoding='UTF-8'?>
<request userid='".$self->params->{credentials}->{user}."' password='".$self->params->{credentials}->{password}."' message-id='1001'>
<add-sip-device account-id='".uri_escape($self->params->{redirect_params}->{profile})."'>
<device-params><deviceId>".$self->content_params->{mac}."</deviceId>
<serialNo>".$self->content_params->{mac}."</serialNo>
<vendor>Polycom</vendor>
<vendorModel>Polycom_UCS_Device</vendorModel>
</device-params>
<sip-device-common-params>
<templateCriteria>".uri_escape($self->params->{redirect_params}->{profile})."</templateCriteria>
</sip-device-common-params>
<package-data><base-package-name>default</base-package-name></package-data>
<vendor-extensions/>
</add-sip-device>
</request>";
    return $self->{register_content};
}

sub unregister_content {
    my $self = shift;
    #.'_'.$self->content_params->{mac}
    $self->{unregister_content} ||=  "<?xml version='1.0' encoding='UTF-8'?>
<request userid='".$self->params->{credentials}->{user}."' password='".$self->params->{credentials}->{password}."' message-id='1001' >
<delete-sip-device account-id='".uri_escape($self->params->{redirect_params}->{profile})."'>
<device-params>
<deviceId>".$self->content_params->{mac}."</deviceId>
<serialNo>".$self->content_params->{mac}."</serialNo>
<vendor>Polycom</vendor>
<vendorModel>Polycom_UCS_Device</vendorModel>
</device-params>
</delete-sip-device>
</request>";
    return $self->{unregister_content};
}
override 'parse_rpc_response_page' => sub {
    my($self, $page) = @_;
    my $xmlDoc = XML::Mini::Document->new();
    $xmlDoc->parse($page);
    my $ref = $xmlDoc->toHash();
    return $ref;
};
override 'parse_rpc_response' => sub {
    my($self, $rpc_response) = @_;
    my $c = $self->params->{c};
    my $ret = 0;
    my ($code,$message) = @{$rpc_response->{response}->{status}}{qw/ErrorCode ErrorMessage/};
    if(0 != $code){
        $ret = $message;
    }
    #todo: configure log4perl (or override) to print out caller info and string
    $c->log->debug("NGCP::Panel::Utils::DeviceBootstrap::Polycom::parse_rpc_response: ret=$ret; code=$code; message=$message;");
    return $ret;
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
