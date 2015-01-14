package NGCP::Panel::Utils::DeviceBootstrap::Polycom;

use strict;
use URI::Escape;
use XML::Simple;
use Data::Dumper;
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
    $cfg->{headers} = { %{$self->get_basic_authorization($self->params->{credentials})} };
    $self->{rpc_server_params} = $cfg;
    return $self->{rpc_server_params};
}
sub register_subscriber_content {
    my $self = shift;
    $self->params->{redirect_params}->{profile} = 'sipwise';
    $self->{register_subscriber_content} ||= "<?xml version='1.0' encoding='UTF-8'?>
<request userid='".$self->params->{credentials}->{user}."' password='".$self->params->{credentials}->{password}."' message-id='1001'>
<create-subscriber account-id='".uri_escape($self->params->{redirect_params}->{profile}.'_'.$self->content_params->{mac})."' isp-name='".uri_escape($self->params->{redirect_params}->{profile})."'>
<PersonalInformation><FirstName></FirstName>
<LastName></LastName>
<password></password>
<address>
<StreetAddress1></StreetAddress1>
<StreetAddress2></StreetAddress2>
<City></City>
<Zipcode></Zipcode>
<Country></Country>
</address>
<select-location></select-location>
<cmmac></cmmac></PersonalInformation></create-subscriber>
</request>";
#<State></State>
#<phone></phone>
    return $self->{register_subscriber_content};
}
sub register_content {
    my $self = shift;
    $self->{register_content} ||= "<?xml version='1.0' encoding='UTF-8'?>
<request userid='".$self->params->{credentials}->{user}."' password='".$self->params->{credentials}->{password}."' message-id='1001'>
<add-sip-device account-id='".uri_escape($self->params->{redirect_params}->{profile}.'_'.$self->content_params->{mac})."'>
<device-params><deviceId>".$self->content_params->{mac}."</deviceId>
<serialNo>".$self->content_params->{mac}."</serialNo>
<vendor>Polycom</vendor>
<vendorModel>Polycom_UCS_Device</vendorModel>
</device-params>
<sip-device-common-params>
<templateCriteria>".uri_escape($self->params->{redirect_params}->{profile})."</templateCriteria>
</sip-device-common-params>
<package-data><base-package-name>default</base-package-name>
</package-data></add-sip-device>
</request>";
    return $self->{register_content};
}

sub unregister_content {
    my $self = shift;
    $self->{unregister_content} ||=  "<?xml version='1.0' encoding='UTF-8'?>
<request userid='".$self->params->{credentials}->{user}."' password='".$self->params->{credentials}->{password}."' message-id='1001' >
<delete-sip-device account-id='".uri_escape($self->params->{redirect_params}->{profile}.'_'.$self->content_params->{mac})."'>
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
sub register{
    my($self) = @_;
    $self->rpc_server_params;
    $self->redirect_server_call('register_subscriber');
    return $self->redirect_server_call('register');
}
override 'parse_rpc_response_page' => sub {
    my($self, $page) = @_;
    #my $xs = XML::Simple->new();
    #my $ref = $xs->XMLin($page);
    my $ref = {};
    return $ref;
};
override 'parse_rpc_response' => sub {
    my($self, $rpc_response) = @_;
    my $c = $self->params->{c};
    my ($code,$message) = @{$rpc_response->{status}}{qw/ErrorCode ErrorMessage/};
    if(0 != $code){
        return $message;
    }
    return 0;
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
