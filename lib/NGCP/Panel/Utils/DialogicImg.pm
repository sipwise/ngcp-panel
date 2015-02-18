use strict;
use warnings;

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

    has '+serializer' => ( default => \&_set_serializer, );
    1;
}

package NGCP::Panel::Utils::DialogicImg;

use Moo;
use Types::Standard qw(Int HashRef);
use HTTP::Tiny;
with 'Role::REST::Client';    # TODO: dependency

has '+type' => ( default => 'application/xml', is => 'rw' );
has '+serializer_options' => (default => sub {
        my $s = Data::Serializer::Raw->new(
            serializer => 'XML::Simple',
            options    => { RootName => 'object' } );
        return { serializer  => $s };
    });
has 'appid' => ( is => 'rw', isa => Int, default => 0 );
has 'pids' => (
    is      => 'rw',
    isa     => HashRef,
    default => sub {
        return {
            bn2020               => 10_001, # defaults (should be overwritten)
            network              => 10_002,
            interface_collection => 10_003,
            interface            => 10_004,
        };
    } );

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
        $data,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{bn2020} = $resp->data->{oid};
    }
    return $resp;
}

sub create_network {
    my ($self) = @_;

    my $pid   = $self->pids->{bn2020};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/NetworkInterfaces/NULL?pid=$pid&appid=$appid",
    );
    return $resp if ( $resp->code != 200 );
    my $new_resp = $self->_build_response_data( $resp->data, $pid );
    $resp = $self->post(
        "/oamp/configuration/objects/NetworkInterfaces/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{network} = $resp->data->{oid};
    }
    return $resp;
}

sub create_interface_collection {
    my ($self) = @_;

    my $pid   = $self->pids->{network};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/NetworkLogicalInterfaces/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid );
    $resp = $self->post(
        "/oamp/configuration/objects/NetworkLogicalInterfaces/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{interface_collection} = $resp->data->{oid};
    }
    return $resp;
}

sub create_interface {
    my ($self) = @_;

    my $pid   = $self->pids->{interface_collection};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/NetworkLogicalInterface/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid );
    $resp = $self->post(
        "/oamp/configuration/objects/NetworkLogicalInterface/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        if ( $resp->data->{property}{Interface}{value} eq "Control" ) {
            $self->pids->{interface_control} = $resp->data->{oid};
        } elsif ( $resp->data->{property}{Interface}{value} eq "Data A" ) {
            $self->pids->{interface_dataa} = $resp->data->{oid};
        }
        $self->pids->{interface} = $resp->data->{oid};

    }
    return $resp;
}

#TODO: only supports ipv4 now
sub create_ip_address {
    my ( $self, $options ) = @_;

    if ( defined $options->{NIIPAddress} && !defined $options->{NIIPGateway} )
    {
        $options->{NIIPGateway} = $options->{NIIPAddress} =~ s/\.[0-9]+$/.1/r;
    }
    my $data  = $self->objects->{bn2020};
    my $pid   = $self->pids->{interface};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/NetworkInterface/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/NetworkInterface/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{interface} = $resp->data->{oid};
    }
    return $resp;
}

sub create_facility {
    my ($self) = @_;

    my $pid   = $self->pids->{bn2020};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/Facility/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid );
    $resp
        = $self->post(
        "/oamp/configuration/objects/Facility/NULL?pid=$pid&appid=$appid",
        $new_resp, );
    if ( $resp->code == 200 ) {
        $self->pids->{facility} = $resp->data->{oid};

    }
    return $resp;
}

sub create_packet_facility_collection {
    my ($self) = @_;

    my $pid   = $self->pids->{facility};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/PacketFacilities/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid );
    $resp
        = $self->post(
        "/oamp/configuration/objects/PacketFacilities/NULL?pid=$pid&appid=$appid",
        $new_resp, );
    if ( $resp->code == 200 ) {
        $self->pids->{packet_facility_collection} = $resp->data->{oid};

    }
    return $resp;
}

sub create_packet_facility {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{packet_facility_collection};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/PacketFacility/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/PacketFacility/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{packet_facility} = $resp->data->{oid};
    }
    return $resp;
}

sub create_signaling {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{bn2020};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/Signaling/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/Signaling/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{signaling} = $resp->data->{oid};
    }
    return $resp;
}

sub create_sip {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{signaling};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/SIP/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/SIP/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{sip} = $resp->data->{oid};
    }
    return $resp;
}

sub create_sip_ip {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{sip};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/SIPIP/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/SIPIP/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{sip_ip} = $resp->data->{oid};
    }
    return $resp;
}

sub create_profile_collection {
    my ( $self, $options ) = @_;

    my $pid   = 10000;
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/Profiles/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/Profiles/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{profile_collection} = $resp->data->{oid};
    }
    return $resp;
}

sub create_ip_profile_collection {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{profile_collection};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/IPProfiles/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/IPProfiles/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{ip_profile_collection} = $resp->data->{oid};
    }
    return $resp;
}

sub create_ip_profile {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{ip_profile_collection};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/IPProfile/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/IPProfile/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{ip_profile} = $resp->data->{oid};
    }
    return $resp;
}

sub create_vocoder_profile {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{ip_profile};
    my $appid = $self->appid;
    my $enc_data =  $self->_urlencode_data($options);
    my $resp  = $self->get(
        "/oamp/configuration/objects/VocoderProfile/NULL?detaillevel=4&pid=$pid&appid=$appid&$enc_data",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource second time (revalidate)\n";
        return $resp;
    }
    my $validation_data = $self->_build_validation_data( $resp->data, $pid, $options );
    $resp = $self->get(
        "/oamp/configuration/objects/VocoderProfile/NULL",
        $validation_data,
    );
    my $new_data = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/VocoderProfile/NULL?pid=$pid&appid=$appid",
        $new_data,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{vocoder_profile} = $resp->data->{oid};
    }
    return $resp;
}

sub create_sip_profile_collection {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{profile_collection};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/SIPProfiles/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_resp = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/SIPProfiles/NULL?pid=$pid&appid=$appid",
        $new_resp,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{sip_profile_collection} = $resp->data->{oid};
    }
    return $resp;
}

sub create_sip_profile {
    my ( $self, $options ) = @_;

    my $pid   = $self->pids->{sip_profile_collection};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/SIPSGP/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_data = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/SIPSGP/NULL?pid=$pid&appid=$appid",
        $new_data,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{sip_profile} = $resp->data->{oid};
    }
    return $resp;
}

sub create_routing_configuration {
    my ($self) = @_;

    my $pid   = 10_000;
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/RoutingConfiguration/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_data = $self->_build_response_data( $resp->data, $pid );
    $resp = $self->post(
        "/oamp/configuration/objects/RoutingConfiguration/NULL?pid=$pid&appid=$appid",
        $new_data,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{routing_configuration} = $resp->data->{oid};
    }
    return $resp;
}

sub create_channel_group_collection {
    my ($self) = @_;

    my $pid   = $self->pids->{routing_configuration};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/ChannelGroups/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_data = $self->_build_response_data( $resp->data, $pid );
    $resp = $self->post(
        "/oamp/configuration/objects/ChannelGroups/NULL?pid=$pid&appid=$appid",
        $new_data,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{channel_group_collection} = $resp->data->{oid};
    }
    return $resp;
}

sub create_channel_group {
    my ($self, $options) = @_;

    my $pid   = $self->pids->{channel_group_collection};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/ChannelGroup/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "Failed to fetch resource\n";
        return $resp;
    }
    my $new_data = $self->_build_response_data( $resp->data, $pid, $options);
    $resp = $self->post(
        "/oamp/configuration/objects/ChannelGroup/NULL?pid=$pid&appid=$appid",
        $new_data,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{channel_group} = $resp->data->{oid};
    }
    return $resp;
}

### OTHER STUFF ###

sub download_profiles {
    my ($self) = @_;

    my $appid = $self->appid;
    my $pid = $self->pids->{profile_collection};
    $self->set_header( 'Content-Length' => '0', );
    my $resp = $self->put(
        "/oamp/configuration/objects/Profiles/$pid/provisions/Cached?appid=$appid&sync_key=0",
    );
    return $resp;
}

#delete all children of bn2020 but not the node itself
sub delete_all_bn2020 {
    my ($self) = @_;

    my $pid   = $self->pids->{bn2020};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects?appid=$appid",
    );
    if ($resp->code != 200) {
        warn "failed to get objects\n";
        return $resp;
    }
    my $root = $resp->data->{object}[0]; #bn2020
    for my $ch (_get_all_children($root)) {
        $self->_recursive_delete($ch);
    }

    return $resp;
}

sub _get_all_children {
    my $node = shift;
    if (defined $node->{object}) {
        if ("HASH" eq ref $node->{object}) {
            return ($node->{object},);
        }
        elsif ("ARRAY" eq ref $node->{object}) {
            return @{ $node->{object} };
        }
    }
    return ();
}

sub _recursive_delete {
    my ($self, $node) = @_;
    my $classname = $node->{classname};
    my $oid = $node->{oid};
    my $appid = $self->appid;
    for my $ch (_get_all_children($node)) {
        $self->_recursive_delete($ch);
    }
    return if $classname eq "Node"; # don't delete the bn2020 object (causes reboot)
    my $path = "/oamp/configuration/objects/$classname/$oid?appid=$appid&sync_key=0";
    $self->set_header( 'Content-Length' => '0', );
    my $resp = $self->delete($path);
    #use DDP; p $path; p $resp->code;
    return;
}

sub reboot_and_wait {
    my ($self) = @_;

    my $appid = $self->appid;

    $self->set_header( 'Content-Length' => '0', );
    # my $resp = $self->delete("/oamp/configuration/database/new?appid=$appid",
    #     '<database name="boot.xml"/>');
    my $resp = $self->_request_with_body("DELETE",
        "/oamp/configuration/database/new?appid=$appid",
        '<database name="boot.xml"/>');
    if ($resp->code != 200) {
        warn "failed to reset config\n";
        return $resp;
    }
    sleep 2; # not to catch the old server
    for (my $i = 0; $i < 40; $i++) { # 200 seconds on 5 seconds timeout
        $resp = $self->get("/");
        last if $resp->code < 500;
    }
    return $resp;
}

sub _build_response_data {
    my ( $self, $req, $pid, $options ) = @_;
    my $resp = {
        pid      => $pid,
        property => {},
    };
    for my $p ( keys %{ $req->{property} } ) {
        # next if "_state_" eq $p;
        # next
        #     if $req->{property}{$p}{visible} eq
        #     "__NULL__";    # TODO: that's SwitchOver
        # next
        #     if ( lc($req->{property}{$p}{readonly}) eq "true" )
        #     && ( lc($req->{property}{$p}{visible}) eq "true" )
        #     && ( lc($req->{property}{$p}{mandatory}) eq "false");
        next
            if lc($req->{property}{$p}{type}) ne "configure";
        $resp->{property}{$p}
            = { configuredvalue => $req->{property}{$p}{value} };
        if ( defined $options->{$p} ) {
            $resp->{property}{$p}{configuredvalue} = $options->{$p};
        }
    }
    return $resp;
}

sub _build_validation_data {
    my ( $self, $req, $pid, $options ) = @_;

    my $response_data = $self->_build_response_data($req, $pid, $options);
    my @changedopt = ();

    if ("HASH" eq ref $options && keys %{ $options }) {
        @changedopt = (
            changedproperty => (keys %{ $options })[0],
            );
    }

    my $resp = {
        pid => $pid,
        appid => $self->appid,
        @changedopt,
    };
    for my $prop (keys %{ $response_data->{property} }) {
        $resp->{$prop} = $response_data->{property}{$prop}{configuredvalue};
    }
    return $resp;
}

sub _build_user_agent { return HTTP::Tiny->new; }

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
                'LicIPChannels' => { 'configuredvalue' => '0' },
            },
            'pid' => '10000',

        },
    };
}

1;

# vim: set tabstop=4 expandtab:
