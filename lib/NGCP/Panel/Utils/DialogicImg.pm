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
use Types::Standard qw(Int HashRef);
use HTTP::Tiny;
with 'Role::REST::Client';    # TODO: dependency

has '+type' => ( default => 'application/xml', is => 'rw' );
has '+serializer_class' => ( is => 'rw', default => sub {'My::Serializer::Plain'} );
has 'appid' => ( is => 'rw', isa => Int, default => 0 );
has 'pids' => (is => 'rw', isa => HashRef, default => sub {return {
        bn2020 => 10001, # defaults (should be overwritten)
        network => 10002,
        interface_collection => 10003,
        interface => 10004,
    };});

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
    if ($resp->code == 200) {
        $self->pids->{bn2020} = $resp->data->{oid};
    }
    return $resp;
}

sub create_network {
    my ($self) = @_;
    my $data = $self->objects->{bn2020};
    my $pid = $self->pids->{bn2020};
    my $appid = $self->appid;
    my $resp = $self->get(
        "/oamp/configuration/objects/NetworkInterfaces/NULL?pid=$pid&appid=$appid",
    );
    return $resp if ($resp->code != 200);
    my $new_resp = $self->_build_response_data($resp->data, $pid);
    $resp = $self->post(
        "/oamp/configuration/objects/NetworkInterfaces/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ($resp->code == 200) {
        $self->pids->{network} = $resp->data->{oid};
    }
    return $resp;
}

sub create_interface_collection {
    my ($self) = @_;

    my $data = $self->objects->{bn2020};
    my $pid = $self->pids->{network};
    my $appid = $self->appid;
    my $resp = $self->get(
        "/oamp/configuration/objects/NetworkLogicalInterfaces/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ($resp->code != 200) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data($resp->data, $pid);
    $resp = $self->post(
        "/oamp/configuration/objects/NetworkLogicalInterfaces/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ($resp->code == 200) {
        $self->pids->{interface_collection} = $resp->data->{oid};
    }
    return $resp;
}

sub create_interface {
    my ($self) = @_;

    my $data = $self->objects->{bn2020};
    my $pid = $self->pids->{interface_collection};
    my $appid = $self->appid;
    my $resp = $self->get(
        "/oamp/configuration/objects/NetworkLogicalInterface/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ($resp->code != 200) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data($resp->data, $pid);
    $resp = $self->post(
        "/oamp/configuration/objects/NetworkLogicalInterface/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ($resp->code == 200) {
        if ($resp->data->{property}{Interface}{value} eq "Control") {
            $self->pids->{interface_control} = $resp->data->{oid};
        } elsif ($resp->data->{property}{Interface}{value} eq "Data A") {
            $self->pids->{interface_dataa} = $resp->data->{oid};
        }
        $self->pids->{interface} = $resp->data->{oid};

    }
    return $resp;
}

#TODO: only supports ipv4 now
sub create_ip_address {
    my ($self, $options) = @_;

    if (defined $options->{NIIPAddress} && ! defined $options->{NIIPGateway} ) {
        $options->{NIIPGateway} = $options->{NIIPAddress} =~ s/\.[0-9]+$/.1/r;
    }
    my $data = $self->objects->{bn2020};
    my $pid = $self->pids->{interface};
    my $appid = $self->appid;
    my $resp = $self->get(
        "/oamp/configuration/objects/NetworkInterface/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ($resp->code != 200) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data($resp->data, $pid, $options);
    $resp = $self->post(
        "/oamp/configuration/objects/NetworkInterface/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ($resp->code == 200) {
        $self->pids->{interface} = $resp->data->{oid};
    }
    return $resp;
}


sub _build_response_data {
    my ($self, $req, $pid, $options) = @_;
    my $resp = {
        pid => $pid,
        property => {},
    };
    for my $p(keys %{ $req->{property} }) {
        next if "_state_" eq $p;
        next if $req->{property}{$p}{visible} eq "__NULL__"; # TODO: that's SwitchOver
        next if ($req->{property}{$p}{readonly} eq "True") &&
                ($req->{property}{$p}{visible} eq "true");
        $resp->{property}{$p} = {configuredvalue => $req->{property}{$p}{value}};
        if (defined $options->{$p}) {
            $resp->{property}{$p}{configuredvalue} = $options->{$p};
        }
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
