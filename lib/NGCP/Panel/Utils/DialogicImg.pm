{

    package My::Serializer::Plain;
    use Moo;
    extends 'Role::REST::Client::Serializer';

    # sub serialize {
    #     return {"foo" => "bar"};
    # }

    # sub deserialize {
    #     my ($self, $content) = @_;
    #     return "new content!!";
    # }

    sub _set_serializer {
        my $s = Data::Serializer::Raw->new(
            serializer => 'XML::Simple',
            options    => { RootName => 'object' } );
        return $s;
    }

    has '+serializer' => (
        default => \&_set_serializer,
        );

    1;
}

package NGCP::Panel::Utils::DialogicImg;

use strict;
use warnings;
use Moo;
use Types::Standard qw(Int);
use HTTP::Tiny;
with 'Role::REST::Client';    # TODO: dependency

has '+type' => ( default => 'application/xml', is => 'rw' );
has '+serializer_class' => ( is => 'rw', default => sub {'My::Serializer::Plain'} );
has 'appid' => ( is => 'rw', isa => Int, default => 0 );

sub login {
    my ( $self, $username, $password ) = @_;
    my $resp = $self->post(
        '/oamp/user_management/users/logged_in?appid=0',
        { user => { name => $username, password => $password } } );
    my $code = $resp->code;
    my $data = $resp->data;
    if ( $code == 200 ) {
        $self->appid( $data->{appid} );
        return $self->appid;
    }
}

sub obtain_lock {
    my ($self) = @_;
    $self->set_header( 'Content-Length' => '0', );
    my $resp = $self->delete(
        '/oamp/user_management/locks?appid=' . $self->appid );
    $resp = $self->post( '/oamp/user_management/locks?appid=' . $self->appid,
        {} );
    return $resp;
}

sub create_bn2020 {
    my ($self) = @_;
    my $data = $self->objects->{bn2020};
    my $resp = $self->post(
        '/oamp/configuration/objects/Node/NULL?pid=10000&appid='
            . $self->appid,
        $data
    );
    return $resp;
}

sub create_network {
    my ($self) = @_;
    my $data = $self->objects->{bn2020};
    my $resp = $self->get(
        '/oamp/configuration/objects/NetworkInterfaces/NULL?pid=10001&appid='
            . $self->appid,
    );
    return $resp if ($resp->code != 200);
    my $new_resp = $self->_build_response_data($resp->data);
    $resp = $self->post(
        '/oamp/configuration/objects/NetworkInterfaces/NULL?pid=10001&appid='
            . $self->appid,
        $new_resp,
    );
    
    return $resp;
}

sub _build_response_data {
    my ($self, $req) = @_;
    my $resp = {
        pid => 10001,
        property => {},
    };
    for my $p(keys %{ $req->{property} }) {
        $resp->{property}{$p} = {configuredvalue => $req->{property}{$p}{value}};
    }
    return $resp;
}

sub _build_user_agent { HTTP::Tiny->new }

sub objects {
    return {
        bn2020 => {
            'property' => {
                'IPType'              => { 'configuredvalue' => 'IPv4' },
                '_position_'          => { 'configuredvalue' => '' },
                '_localDbSyncKey_'    => { 'configuredvalue' => '0' },
                'PacketAudioChannels' => { 'configuredvalue' => 'Unknown' },
                'CFCMode'             => { 'configuredvalue' => 'Unknown' },
                'srtpEnable'          => { 'configuredvalue' => 'Disabled' },
                'InterfaceType'       => { 'configuredvalue' => 'Unknown' },
                'MediaMode'           => { 'configuredvalue' => 'Audio LBR' },
                'SwVersion'           => { 'configuredvalue' => 'Unknown' },
                'SubNetMask'          => { 'configuredvalue' => '' },
                'Name'                => { 'configuredvalue' => 'Node0' },
                'ResendLogic'         => { 'configuredvalue' => 'Disable' },
                'PacketMultimediaChannels' =>
                    { 'configuredvalue' => 'Unknown' },
                'NetworkMultimediaChannels' =>
                    { 'configuredvalue' => 'Unknown' },
                'IPAddress'  => { 'configuredvalue' => '' },
                'ACLName'    => { 'configuredvalue' => 'Unrestricted' },
                'NodeType'   => { 'configuredvalue' => 'Unknown' },
                'ACL_ID'     => { 'configuredvalue' => '0' },
                'IPChannels' => { 'configuredvalue' => 'Unknown' },
                'ID'         => { 'configuredvalue' => '0' },
                '_objectName_' =>
                    { 'configuredvalue' => 'BN2020: Node0 - ID: 0' },
                'LicIPChannels' => { 'configuredvalue' => '0' }
            },
            'pid' => '10000'

        },
    };
}

1;

# vim: set tabstop=4 expandtab:
