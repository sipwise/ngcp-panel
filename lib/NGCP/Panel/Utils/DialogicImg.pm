use strict;
use warnings;
{
    package My::Serializer::Custom;
    use Moo;
    extends 'Role::REST::Client::Serializer';

    sub _set_serializer {
        my $s = Data::Serializer::Raw->new(
            serializer => 'XML::Simple',
            options    => {
                RootName => 'object',
                # KeyAttr => { 'object' => '+classname' },
                # ForceArray => ['IPProfile'],
            } );
        return $s;
    }

    has '+serializer' => ( default => \&_set_serializer, );
    1;
}

package NGCP::Panel::Utils::DialogicImg;

use Moo;
use Digest::MD5 qw/md5_hex/;
use HTTP::Tiny;
use Storable qw/freeze/;
use Types::Standard qw(Int HashRef);
with 'Role::REST::Client';

has '+type' => ( default => 'application/xml', is => 'rw' );
# has '+serializer_options' => (default => sub {
#         my $s = Data::Serializer::Raw->new(
#             serializer => 'XML::Simple',
#             options    => { RootName => 'object' } );
#         return { serializer  => $s };
#     });
has '+serializer_class' =>
    ( is => 'rw', default => sub {'My::Serializer::Custom'} );
has '+clientattrs' => ( default => sub {
        return {timeout => 5};
    });
has 'appid' => ( is => 'rw', isa => Int, default => 0 );
has 'pids' => (
    is      => 'rw',
    isa     => HashRef,
    default => sub {
        return {
            root                 => 10_000,
            bn2020               => 10_001,
        };
    } );

has 'classinfo' => ( is => 'ro', isa => HashRef, default => sub{
    return {
        bn2020 => {  # dummy, not used by _create_generic
            name => 'Node',
            parent => 'root',
            revalidate => 0,
        },
        network => {
            name => 'NetworkInterfaces',
            parent => 'bn2020',
            revalidate => 0,
        },
        interface_collection => {
            name => 'NetworkLogicalInterfaces',
            parent => 'network',
            revalidate => 0,
        },
        interface => {
            name => 'NetworkLogicalInterface',
            parent => 'interface_collection',
            revalidate => 0,
        },
        ip_address => {
            name => 'NetworkInterface',
            parent => 'interface',
            revalidate => 1,
        },
        facility => {
            name => 'Facility',
            parent => 'bn2020',
            revalidate => 0,
        },
        packet_facility_collection => {
            name => 'PacketFacilities',
            parent => 'facility',
            revalidate => 0,
        },
        packet_facility => {
            name => 'PacketFacility',
            parent => 'packet_facility_collection',
            revalidate => 0,
        },
        ds1_spans => {
            name => 'SpanGroup',
            parent => 'facility',
            revalidate => 0,
        },
        ds3_optical => {
            name => 'DS3_Optical',
            parent => 'facility',
            revalidate => 1,
        },
        optical_interface => {
            name => 'Optical_Interface',
            parent => 'ds3_optical',
            revalidate => 0,
        },
        optical_link => {
            name => 'Optical_Link',
            parent => 'optical_interface',
            revalidate => 0,
        },
        ds3_interface => {
            name => 'TDM_DS3',
            parent => 'optical_interface',
            revalidate => 0,
        },
        ds1_spans_optical => {
            name => 'SpanGroup', # TODO: double occurence, is that acceptable?
            parent => 'ds3_interface',
            revalidate => 0,
        },
        signaling => {
            name => 'Signaling',
            parent => 'bn2020',
            revalidate => 0,
        },
        isdn => {
            name => 'ISDN',
            parent => 'signaling',
            revalidate => 0,
        },
        isdn_d_chan => {
            name => 'ISDNDChan',
            parent => 'isdn',
            revalidate => 1,
        },
        isdn_group => {
            name => 'ISDNGroup',
            parent => 'isdn_d_chan',
            revalidate => 0,
        },
        isdn_circuit_group => {
            name => 'ISDNCircuitGroup',
            parent => 'isdn_group',
            revalidate => 1,
        },
        sip => {
            name => 'SIP',
            parent => 'signaling',
            revalidate => 0,
        },
        sip_ip => {
            name => 'SIPIP',
            parent => 'sip',
            revalidate => 0,
        },
        call_tracing => {
            name => 'CallTracing',
            parent => 'bn2020',
            revalidate => 0,
        },
        snmp_agent => {
            name => 'SNMPClient',
            parent => 'bn2020',
            revalidate => 0,
        },
        ss7 => {
            name => 'SS7',
            parent => 'root',
            revalidate => 0,
        },
        ss7_network => {
            name => 'SS7Network',
            parent => 'ss7',
            revalidate => 0,
        },
        ss7_node_collection => {
            name => 'SS7Nodes',
            parent => 'ss7_network',
            revalidate => 0,
        },
        ss7_node_primary => {
            name => 'SS7PrimaryNode',
            parent => 'ss7_node_collection',
            revalidate => 0,
        },
        ss7_stack => {
            name => 'SS7Stack',
            parent => 'ss7_network',
            revalidate => 1,
        },
        ss7_link_set => {
            name => 'SS7LinkSet',
            parent => 'ss7_stack',
            revalidate => 1,
        },
        ss7_link => {
            name => 'SS7Link',
            parent => 'ss7_link_set',
            revalidate => 1,
        },
        ss7_destination => {
            name => 'SS7Destination',
            parent => 'ss7_stack',
            revalidate => 1,
        },
        ss7_route => {
            name => 'SS7Route',
            parent => 'ss7_destination',
            revalidate => 1,
        },
        ss7_isup_group => {  # note: needs isup profile
            name => 'ISUPGroup',
            parent => 'ss7_destination',
            revalidate => 1,
        },
        ss7_circuit_group => {
            name => 'SS7CircuitGroup',
            parent => 'ss7_isup_group',
            revalidate => 1,
        },
        profile_collection => {
            name => 'Profiles',
            parent => 'root',
            revalidate => 0,
        },
        ip_profile_collection => {
            name => 'IPProfiles',
            parent => 'profile_collection',
            revalidate => 0,
        },
        ip_profile => {
            name => 'IPProfile',
            parent => 'ip_profile_collection',
            revalidate => 1,
        },
        vocoder_profile => {
            name => 'VocoderProfile',
            parent => 'ip_profile',
            revalidate => 1,
        },
        sip_profile_collection => {
            name => 'SIPProfiles',
            parent => 'profile_collection',
            revalidate => 0,
        },
        sip_profile => {
            name => 'SIPSGP',
            parent => 'sip_profile_collection',
            revalidate => 0,
        },
        tdm_profile_collection => {
            name => 'TDMProfiles',
            parent => 'profile_collection',
            revalidate => 0,
        },
        e1_profile => {
            name => 'E1Profile',
            parent => 'tdm_profile_collection',
            revalidate => 0,
        },
        isup_profile_collection => {
            name => 'ISUPProfiles',
            parent => 'profile_collection',
            revalidate => 0,
        },
        isup_itu_profile => {
            name => 'ISUP_ITUProfile',
            parent => 'isup_profile_collection',
            revalidate => 0,
        },
        isup_ansi_profile => {
            name => 'ISUP_ANSIProfile',
            parent => 'isup_profile_collection',
            revalidate => 0,
        },
        external_network_elements => {
            name => 'ExternalNetworkElements',
            parent => 'root',
            revalidate => 0,
        },
        external_gateway_collection => {
            name => 'ExternalGateways',
            parent => 'external_network_elements',
            revalidate => 0,
        },
        external_gateway => {
            name => 'ExternalGateway',
            parent => 'external_gateway_collection',
            revalidate => 1,
        },
        external_nfsserver_collection => {
            name => 'NFSServers',
            parent => 'external_network_elements',
            revalidate => 0,
        },
        external_nfsserver => {
            name => 'NFSServer',
            parent => 'external_nfsserver_collection',
            revalidate => 1,
        },
        external_snmpmanager_collection => {
            name => 'SNMPServers',
            parent => 'external_network_elements',
            revalidate => 0,
        },
        external_snmpmanager => {
            name => 'SNMPServer',
            parent => 'external_snmpmanager_collection',
            revalidate => 1,
        },
        routing_configuration => {
            name => 'RoutingConfiguration',
            parent => 'root',
            revalidate => 0,
        },
        channel_group_collection => {
            name => 'ChannelGroups',
            parent => 'routing_configuration',
            revalidate => 0,
        },
        channel_group => {
            name => 'ChannelGroup',
            parent => 'channel_group_collection',
            revalidate => 1,
        },
        route_table_collection => {
            name => 'RoutingTables',
            parent => 'routing_configuration',
            revalidate => 0,
        },
        route_table => {
            name => 'RouteTable',
            parent => 'route_table_collection',
            revalidate => 1,
        },
        route_element => {
            name => 'RouteElement',
            parent => 'route_table',
            revalidate => 1,
        },
        cg_network_element => {
            name => 'NetworkElement',
            parent => 'channel_group',
            revalidate => 0,
        },
        node_association => {
            name => 'NodeAssociation',
            parent => 'cg_network_element',
            revalidate => 0,
        },
        cg_isdn_circuit_group => {
            name => 'SSLCircuitGroup',
            parent => 'channel_group',
            revalidate => 0,
        },
    };
    });

# returns appid or 0
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
    return 0;
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

###### CREATE methods ######

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

    return $self->_create_generic(undef, 'network');
}

sub create_interface_collection {
    my ($self) = @_;

    return $self->_create_generic(undef, 'interface_collection');
}

sub create_interface {
    my ($self) = @_;

    my $resp = $self->_create_generic(undef, 'interface');
    if ( $resp->code == 200 ) {
        if ( $resp->data->{property}{Interface}{value} eq "Control" ) {
            $self->pids->{interface_control} = $resp->data->{oid};
        } elsif ( $resp->data->{property}{Interface}{value} eq "Data A" ) {
            $self->pids->{interface_dataa} = $resp->data->{oid};
        }
    }
    return $resp;
}

sub create_ip_address {
    my ( $self, $options ) = @_;

    if ( defined $options->{NIIPAddress} && !defined $options->{NIIPGateway} )
    {
        $options->{NIIPGateway} = $options->{NIIPAddress} =~ s/\.[0-9]+$/.1/r;
    }
    return $self->_create_generic($options, 'ip_address');
}

sub create_facility {
    my ($self) = @_;

    return $self->_create_generic(undef, 'facility');
}

sub create_packet_facility_collection {
    my ($self) = @_;

    return $self->_create_generic(undef, 'packet_facility_collection');
}

sub create_packet_facility {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'packet_facility');
}

sub create_ds1_spans {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ds1_spans');
}

sub create_ds3_optical {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ds3_optical');
}

sub create_optical_interface {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'optical_interface');
}

sub create_optical_link {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'optical_link');
}

sub create_ds3_interface {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ds3_interface');
}

sub create_ds1_spans_optical {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ds1_spans_optical');
}

sub create_signaling {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'signaling');
}

sub create_isdn {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'isdn');
}

sub create_isdn_d_chan {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'isdn_d_chan');
}

sub create_isdn_group {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'isdn_group');
}

sub create_isdn_circuit_group {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'isdn_circuit_group');
}

sub create_sip {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'sip');
}

sub create_sip_ip {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'sip_ip');
}

sub create_call_tracing {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'call_tracing');
}

sub create_snmp_agent {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'snmp_agent');
}

sub create_ss7 {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7');
}

sub create_ss7_network {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_network');
}

sub create_ss7_node_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_node_collection');
}

sub create_ss7_node_primary {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_node_primary');
}

sub create_ss7_stack {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_stack');
}

sub create_ss7_link_set {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_link_set');
}

sub create_ss7_link {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_link');
}

sub create_ss7_destination {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_destination');
}

sub create_ss7_route {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_route');
}

sub create_ss7_isup_group {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_isup_group');
}

sub create_ss7_circuit_group {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ss7_circuit_group');
}

sub create_profile_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'profile_collection');
}

sub create_ip_profile_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ip_profile_collection');
}

sub create_ip_profile {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'ip_profile');
}

sub create_vocoder_profile {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'vocoder_profile');
}

sub create_sip_profile_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'sip_profile_collection');
}

sub create_sip_profile {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'sip_profile');
}

sub create_tdm_profile_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'tdm_profile_collection');
}

sub create_e1_profile {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'e1_profile');
}

sub create_isup_profile_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'isup_profile_collection');
}

sub create_isup_itu_profile {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'isup_itu_profile');
}

sub create_isup_ansi_profile {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'isup_ansi_profile');
}

sub create_external_network_elements {
    my ( $self ) = @_;

    return $self->_create_generic(undef, 'external_network_elements');
}

sub create_external_gateway_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'external_gateway_collection');
}

sub create_external_gateway {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'external_gateway');
}

sub create_external_nfsserver_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'external_nfsserver_collection');
}

sub create_external_nfsserver {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'external_nfsserver');
}

sub create_external_snmpmanager_collection {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'external_snmpmanager_collection');
}

sub create_external_snmpmanager {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'external_snmpmanager');
}

sub create_routing_configuration {
    my ($self) = @_;

    return $self->_create_generic(undef, 'routing_configuration');
}

sub create_channel_group_collection {
    my ($self) = @_;

    return $self->_create_generic(undef, 'channel_group_collection');
}

sub create_channel_group {
    my ($self, $options) = @_;

    return $self->_create_generic($options, 'channel_group');
}

sub create_route_table_collection {
    my ($self, $options) = @_;

    return $self->_create_generic($options, 'route_table_collection');
}

sub create_route_table {
    my ($self, $options) = @_;

    return $self->_create_generic($options, 'route_table');
}

sub create_route_element {
    my ($self, $options) = @_;

    return $self->_create_generic($options, 'route_element');
}

sub create_cg_network_element {
    my ($self, $options) = @_;

    return $self->_create_generic($options, 'cg_network_element');
}

sub create_node_association {
    my ($self, $options) = @_;

    return $self->_create_generic($options, 'node_association');
}

sub create_cg_isdn_circuit_group {
    my ( $self, $options ) = @_;

    return $self->_create_generic($options, 'cg_isdn_circuit_group');
}

sub _create_generic {
    my ($self, $options, $class) = @_;

    my $classinfo = $self->classinfo->{$class};
    my $pid   = $self->pids->{$classinfo->{parent}};
    unless ($pid) {
        warn "$class: no valid pid available\n";
        return; # TODO wrong format
    }
    my $classname = $classinfo->{name};
    my $appid = $self->appid;
    my $resp  = $self->get(
        "/oamp/configuration/objects/$classname/NULL?detaillevel=4&pid=$pid&appid=$appid",
    );
    if ( $resp->code != 200 ) {
        warn "$class: Failed to fetch resource\n";
        return $resp;
    }
    if ($classinfo->{revalidate}) {
        my $validation_data = $self->_build_validation_data( $resp->data, $pid, $options );
        $resp = $self->get(
            "/oamp/configuration/objects/$classname/NULL",
            $validation_data,
        );
        if ( $resp->code != 200 ) {
            warn "$class: Failed to fetch resource second time (revalidate)\n";
            return $resp;
        }
    }
    my $new_data = $self->_build_response_data( $resp->data, $pid, $options );
    $resp = $self->post(
        "/oamp/configuration/objects/$classname/NULL?pid=$pid&appid=$appid",
        $new_data,
    );
    if ( $resp->code == 200 ) {
        $self->pids->{$class} = $resp->data->{oid};
    }
    return $resp;
}


# log: 0: none, 1: short, 2: everything
# necessary keys: ip_sip, ip_rtp, ip_client, out_codecs
# optional: in_codecs
# for nfs: ip_nfs_server, nfs_path
# for snmp: snmp_system_name, snmp_system_location, snmp_system_contact, snmp_community_name
# for snmp optional: ip_snmp_manager, snmp_version
sub create_general_part {
    my ($self, $settings, $log) = @_;

    $self->_create_indent;

    my $in_codecs = ['G711 ulaw', 'G711 alaw', 'G729', 'AMR',
        'AMR Bandwidth Efficient', 'AMR-WB', 'AMR-WB Bandwidth Efficient',
        'Clear Channel', 'G723 5.3 Kbps', 'G723 6.3 Kbps', 'G722', 'iLBC 30ms',
        'GSM-FR Static Payload Type', 'GSM-FR Dynamic Payload Type',
        'G726-32/G721 Static Payload Type', 'G726-32/G721 Dynamic Payload Type',
        'GSM-EFR'];

    my $resp = $self->create_bn2020;
    my @in_schedule = map {
            {
                name => 'vocoder_profile', options =>
                    { PayloadType => $_ },
            };
        } @{ $settings->{in_codecs} // $in_codecs };
    my @out_schedule = map {
            {
                name => 'vocoder_profile', options => 
                    { PayloadType => $_ },
            };
        } @{ $settings->{out_codecs} };
    my @nfs_schedule;
    if (defined $settings->{ip_nfs_server} &&
        defined $settings->{nfs_path}) {
        @nfs_schedule = (
            {name => 'external_nfsserver_collection', options => undef}, # needs external_network_elements
            {name => 'external_nfsserver', options => {
                Name => 'ngcp_nfs_server',
                IPAddress => $settings->{ip_nfs_server},
                }},
            {name => 'call_tracing', options => {
                TraceTime => '600',
                MountDirectory => $settings->{nfs_path},
                }},
        );
    }
    my @snmp_schedule;
    if (defined $settings->{snmp_system_name} &&
        defined $settings->{snmp_system_location} &&
        defined $settings->{snmp_system_contact} &&
        defined $settings->{snmp_community_name}) {
        @snmp_schedule = (
            {name => 'external_snmpmanager_collection', options => undef},
            {name => 'external_snmpmanager', options => {
                UserName => 'ngcp',
                CommunityName => $settings->{snmp_community_name},
                ServerIPAddress => $settings->{ip_snmp_manager} // $settings->{ip_client},
                defined $settings->{snmp_version} ? (ServerVersion => $settings->{snmp_version} ) : (),
                }},
            {name => 'snmp_agent', options => {
                SystemName => $settings->{snmp_system_name},
                SystemLoc => $settings->{snmp_system_location},
                SystemContact => $settings->{snmp_system_contact},
                }},
        );
    }
    my $schedule = [
        {name => 'network', options => undef},
        {name => 'interface_collection', options => undef},
        {name => 'interface', options => undef},
        {name => 'ip_address', options => {
            NIIPAddress => $settings->{ip_sip},
            NIIPPhy => 'Services',
            }},
        {name => 'interface', options => undef},
        {name => 'ip_address', options => {
            NIIPAddress => $settings->{ip_rtp},
            NIIPPhy => 'Media 0',
            }},
        {name => 'facility', options => undef},
        {name => 'packet_facility_collection', options => undef},
        {name => 'packet_facility', options => {
            ChannelCount => 50,
            }},
        {name => 'signaling', options => undef},
        {name => 'sip', options => undef},
        {name => 'sip_ip', options => {
            IPAddress => $settings->{ip_sip},
            }},
        {name => 'profile_collection', options => undef},
        {name => 'ip_profile_collection', options => undef},
        {name => 'ip_profile', options => {
            DigitRelay => 'DTMF Packetized',
            Name => 'ngcp_in_profile',
            }},
        @in_schedule,
        {name => 'ip_profile', options => {
            DigitRelay => 'DTMF Packetized',
            Name => 'ngcp_out_profile',
            }},
        @out_schedule,
        {name => 'sip_profile_collection', options => undef},
        {name => 'sip_profile', options => undef},
        #{run => 'download_profiles'},
        {name => 'external_network_elements', options => undef},
        {name => 'external_gateway_collection', options => undef},
        {name => 'external_gateway', options => {
            Name => 'Phone1',
            IPAddress => $settings->{ip_client},
            IPAddress4 => $settings->{ip_client},
            }},
        @nfs_schedule,
        @snmp_schedule,
    ];

    $self->_run_schedule($schedule, $log);

    return 0;
}

# log: 0: none, 1: short, 2: everything
# necessary keys: ip_sip, ip_rtp, ip_client, out_codecs, optional: in_codecs
sub create_all_sipsip {
    my ($self, $settings, $log) = @_;

    $self->create_general_part($settings, $log);
    my $resp;

    my $schedule = [
        {name => 'routing_configuration', options => undef},
        {name => 'channel_group_collection', options => undef},
        {name => 'route_table_collection', options => undef},
        {name => 'route_table', options => {
            Name => 'ngcp_route_table',
            }},
        {name => 'channel_group', options => {
            SignalingType => 'SIP',
            InRouteTable => 'ngcp_route_table - ID: 5',
            InIPProfile => 'ngcp_in_profile',
            InIPProfileId => '1',
            OutIPProfile => 'ngcp_out_profile',
            SupportA2F => 'True',
            Name => 'cg_ngcp_sipclient',
            }},
        {name => 'cg_network_element', options => undef},
        {name => 'node_association', options => undef},
        {name => 'route_element', options => {
            StringType => 'Channel Group',
            InChannelGroup => 'cg_ngcp_sipclient',
            RouteActionType => 'Channel Group',
            RouteActionList => 'cg_ngcp_sipclient',
            }},
        #{run => 'download_route_table'},
        #{run => 'download_channel_groups'},
    ];

    $self->_run_schedule($schedule, $log);

    $self->download_profiles;
    $self->download_route_table;
    $self->download_channel_groups;

    return 0;
}

# log: 0: none, 1: short
# necessary keys: ip_sip, ip_rtp, ip_client, out_codecs, optional: in_codecs
# optional: use_optical_spans (bool), is_isdn_userside (bool)
sub create_all_sipisdn {
    my ($self, $settings, $log) = @_;

    $self->create_general_part($settings, $log);

    my @ds1_spans;
    if ($settings->{use_optical_spans}) {
        @ds1_spans = (
            {name => 'ds3_optical', options => {
                FacilityType => 'Optical',
            }},
            {name => 'optical_interface', options => undef},
            {name => 'optical_link', options => undef},
            {name => 'ds3_interface', options => undef},
            {name => 'ds1_spans_optical', options => undef},
        );
    } else {
        @ds1_spans = (
            {name => 'ds1_spans', options => {
                EndingOffset => '3',
            }},
        );
    }

    my $resp;

    my $schedule = [
        {name => 'isdn', options => undef},

        {name => 'tdm_profile_collection', options => undef},
        {name => 'e1_profile', options => undef},
        @ds1_spans,
        {name => 'isdn_d_chan', options => $settings->{is_isdn_userside} ? 
            {
                BaseVariant => 'Euro-ISDN User Side',
                BChanSelection => 'Linear Counter Clockwise',
            } : undef,
        },
        {name => 'isdn_group', options => undef},
        {name => 'isdn_circuit_group', options => {
            EndChannel => 'Span ID: 0 CID: 30',
            }},
        {name => 'isdn_d_chan', options => $settings->{is_isdn_userside} ? 
            undef : {
                BaseVariant => 'Euro-ISDN User Side',
                BChanSelection => 'Linear Counter Clockwise',
            },
        },
        {name => 'isdn_group', options => undef},
        {name => 'isdn_circuit_group', options => {
            EndChannel => 'Span ID: 1 CID: 30',
            }},
        #{run => 'download_profiles'},
        {name => 'routing_configuration', options => undef},
        {name => 'channel_group_collection', options => undef},
        {name => 'route_table_collection', options => undef},
        {name => 'route_table', options => {
            Name => 'ngcp_route_table',
            }},
        {name => 'channel_group', options => {
            SignalingType => 'SIP',
            InRouteTable => 'ngcp_route_table - ID: 5',
            InIPProfile => 'ngcp_in_profile',
            InIPProfileId => '1',
            OutIPProfile => 'ngcp_out_profile',
            SupportA2F => 'True',
            Name => 'cg_ngcp_sipclient',
            }},
        {name => 'cg_network_element', options => undef},
        {name => 'node_association', options => undef},
        {name => 'channel_group', options => {
            SignalingType => 'ISDN',
            InRouteTable => 'ngcp_route_table - ID: 5',
            SupportA2F => 'True',
            Name => 'cg_ngcp_isdn_1',
            }},
        {name => 'cg_isdn_circuit_group', options => undef},
        {name => 'channel_group', options => {
            SignalingType => 'ISDN',
            InRouteTable => 'ngcp_route_table - ID: 5',
            SupportA2F => 'True',
            Name => 'cg_ngcp_isdn_2',
            }},
        {name => 'cg_isdn_circuit_group', options => undef},
        {name => 'route_element', options => {
            StringType => 'Channel Group',
            InChannelGroup => 'cg_ngcp_sipclient',
            RouteActionType => 'Channel Group',
            RouteActionList => 'cg_ngcp_isdn_1',
            }},
        {name => 'route_element', options => {
            StringType => 'Channel Group',
            InChannelGroup => 'cg_ngcp_isdn_1',
            RouteActionType => 'Channel Group',
            RouteActionList => 'cg_ngcp_sipclient',
            }},
        {name => 'route_element', options => {
            StringType => 'Channel Group',
            InChannelGroup => 'cg_ngcp_isdn_2',
            RouteActionType => 'Channel Group',
            RouteActionList => 'cg_ngcp_sipclient',
            }},
        #{run => 'download_route_table'},
        #{run => 'download_channel_groups'},
    ];

    $self->_run_schedule($schedule, $log);

    $self->download_profiles;
    $self->download_route_table;
    $self->download_channel_groups;

    return 0;
}

# log: 0: none, 1: short
# necessary keys: ip_sip, ip_rtp, ip_client, out_codecs, ss7_opc, ss7_apc, ss7_dpc
# optionalkeys: in_codecs
# optional: use_optical_spans (bool)
sub create_all_sipss7 {
    my ($self, $settings, $log) = @_;

    $self->create_general_part($settings, $log);

    my @ds1_spans;
    if ($settings->{use_optical_spans}) {
        @ds1_spans = (
            {name => 'ds3_optical', options => {
                FacilityType => 'Optical',
            }},
            {name => 'optical_interface', options => undef},
            {name => 'optical_link', options => undef},
            {name => 'ds3_interface', options => undef},
            {name => 'ds1_spans_optical', options => undef},
        );
    } else {
        @ds1_spans = (
            {name => 'ds1_spans', options => {
                EndingOffset => '3',
            }},
        );
    }

    my $resp;

    my $schedule = [
        {name => 'tdm_profile_collection', options => undef},
        {name => 'e1_profile', options => undef},
        {name => 'isup_profile_collection', options => undef},
        {name => 'isup_itu_profile', options => undef},
        @ds1_spans,
        #{run => 'download_profiles'},
        {name => 'ss7', options => undef},
        {name => 'ss7_network', options => undef},
        {name => 'ss7_node_collection', options => undef},
        {name => 'ss7_node_primary', options => undef},
        {name => 'ss7_stack', options => {
            OPC => $settings->{ss7_opc},
        }},
        {name => 'ss7_link_set', options => {
            APC => $settings->{ss7_apc},
        }},
        {name => 'ss7_link', options => undef},
        {name => 'ss7_destination', options => {
            DPC => $settings->{ss7_dpc},
        }},
        {name => 'ss7_route', options => {
            Linkset => 'SS7 Link Set APC: ' . $settings->{ss7_apc},
        }},
        {name => 'ss7_isup_group', options => undef},
        {name => 'ss7_circuit_group', options => {
            StartCIC => '1',
        }},

        {name => 'ss7_stack', options => {  # for loopback purposes
            OPC => $settings->{ss7_dpc},
        }},
        {name => 'ss7_link_set', options => {
            APC => $settings->{ss7_opc},
        }},
        {name => 'ss7_link', options => undef},
        {name => 'ss7_destination', options => {
            DPC => $settings->{ss7_opc},
        }},
        {name => 'ss7_route', options => {
            Linkset => 'SS7 Link Set APC: ' . $settings->{ss7_opc},
        }},
        {name => 'ss7_isup_group', options => undef},
        {name => 'ss7_circuit_group', options => {
            StartCIC => '1',
        }},

        {name => 'routing_configuration', options => undef},
        {name => 'channel_group_collection', options => undef},
        {name => 'route_table_collection', options => undef},
        {name => 'route_table', options => {
            Name => 'ngcp_route_table',
            }},
        {name => 'channel_group', options => {
            SignalingType => 'SIP',
            InRouteTable => 'ngcp_route_table - ID: 5',
            InIPProfile => 'ngcp_in_profile',
            InIPProfileId => '1',
            OutIPProfile => 'ngcp_out_profile',
            SupportA2F => 'True',
            Name => 'cg_ngcp_sipclient',
            }},
        {name => 'cg_network_element', options => undef},
        {name => 'node_association', options => undef},

        {name => 'channel_group', options => {
            SignalingType => 'SS7_ISUP',
            InRouteTable => 'ngcp_route_table - ID: 5',
            SupportA2F => 'True',
            Name => 'cg_ngcp_ss7_1',
            }},
        {name => 'cg_isdn_circuit_group', options => undef},
        {name => 'channel_group', options => {
            SignalingType => 'SS7_ISUP',
            InRouteTable => 'ngcp_route_table - ID: 5',
            SupportA2F => 'True',
            Name => 'cg_ngcp_ss7_2',
            }},
        {name => 'cg_isdn_circuit_group', options => undef},

        {name => 'route_element', options => {
            StringType => 'Channel Group',
            InChannelGroup => 'cg_ngcp_sipclient',
            RouteActionType => 'Channel Group',
            RouteActionList => 'cg_ngcp_ss7_1',
            }},
        {name => 'route_element', options => {
            StringType => 'Channel Group',
            InChannelGroup => 'cg_ngcp_ss7_1',
            RouteActionType => 'Channel Group',
            RouteActionList => 'cg_ngcp_sipclient',
            }},
        {name => 'route_element', options => {
            StringType => 'Channel Group',
            InChannelGroup => 'cg_ngcp_ss7_2',
            RouteActionType => 'Channel Group',
            RouteActionList => 'cg_ngcp_sipclient',
            }},
        #{run => 'download_route_table'},
        #{run => 'download_channel_groups'},
    ];

    $self->_run_schedule($schedule, $log);

    $self->download_profiles;
    $self->download_route_table;
    $self->download_channel_groups;

    return 0;
}

###### OTHER STUFF ######

sub _run_schedule {
    my ($self, $schedule, $log) = @_;

    my $resp;

    for my $elem (@{ $schedule }) {
        if (exists $elem->{run}) {
            my $command = $elem->{run};
            $self->$command;
            next;
        }
        my ($name, $options) = @{ $elem }{('name', 'options')};
        my $fun = "create_$name";
        $resp = $self->$fun($options);
        # $resp = $self->_create_generic($options, $name);
        if ($log >= 1) {
            my $ind = " " x ($self->classinfo->{$name}{indent}*4);
            printf "%-37s: %d\n", "$ind$name", $resp->code;
            if ($resp->code != 200) {
                use DDP; p $resp->data;
            }
        }
    }

    return 0;
}

sub hash_config {
    my ($self, $config) = @_;
    $Storable::canonical = 1;
    return md5_hex(freeze $config);
}

sub get_config {
    my ($self) = @_;

    my $appid = $self->appid;
    my $resp = $self->get("/oamp/configuration/objects?appid=$appid");
    my $config = {};
    if ($resp->code != 200) {
        warn "failed to get objects\n";
        return $resp;
    }
    my $classinfo = $self->classinfo;
    my $rev_lookup = {};
    @{$rev_lookup}{map {$_->{name}} values %{$classinfo}} = keys %{$classinfo};
    my $root = $resp->data->{object}[0];
    for my $ch (_get_all_children($root)) {
        $self->_recursive_get($ch, $rev_lookup);
    }
    if ($classinfo->{ip_address}{configuredids}[0]) {
        ($config->{ip1}) = $self->_get_specifics(
            'ip_address', $classinfo->{ip_address}{configuredids}[0], ['NIIPAddress']);
    }
    if ($classinfo->{ip_address}{configuredids}[1]) {
        ($config->{ip2}) = $self->_get_specifics(
            'ip_address', $classinfo->{ip_address}{configuredids}[1], ['NIIPAddress']);
    }
    if ($classinfo->{external_gateway}{configuredids}[0]) {
        ($config->{ip_client}) = $self->_get_specifics(
            'external_gateway', $classinfo->{external_gateway}{configuredids}[0], ['IPAddress']);
    }
    if (exists $classinfo->{vocoder_profile}{configuredids}) {
        for my $id (@{ $classinfo->{vocoder_profile}{configuredids} }) {
            push @{ $config->{in_codecs} }, $self->_get_specifics(
            'vocoder_profile', $id, ['PayloadType']);
        }
    }
    return $config;
}

sub _recursive_get {
    my ($self, $node, $rev_lookup) = @_;
    my $classname = $node->{classname};
    my $oname = $rev_lookup->{$classname};
    my $oid = $node->{oid};
    my $appid = $self->appid;
    for my $ch (_get_all_children($node)) {
        $self->_recursive_get($ch, $rev_lookup);
    }
    if ($oname) {
        $self->pids->{$oname} = $oid;
        push @{ $self->classinfo->{$oname}{configuredids} }, $oid;
    }
    return;
}

sub _get_specifics {
    my ($self, $class, $id, $keys) = @_;

    my $appid = $self->appid;
    my $classinfo = $self->classinfo->{$class};
    my $classname = $classinfo->{name};
    my @res;
    my $resp = $self->get("/oamp/configuration/objects/$classname/$id?appid=$appid&detaillevel=4");
    if ($resp->code != 200) {
        warn "failed to get objects\n";
        return ();
    }
    for my $key (@{ $keys }) {
        push @res, $resp->data->{property}{$key}{value};
    }
    return @res;
}

sub _create_indent {
    my ($self, @class) = @_;
    my $classinfo = $self->classinfo;
    @class = keys %{ $classinfo } unless @class;
    for my $class (@class) {
        next if (exists $classinfo->{$class}{indent});
        my $parent = $classinfo->{$class}{parent};
        if ($parent eq 'root') {
            $classinfo->{$class}{indent} = 0;
        } else {
            $self->_create_indent($parent);
            $classinfo->{$class}{indent} = $classinfo->{$parent}{indent} + 1;
        }
    }
    return;
}

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

sub download_route_table {
    my ($self) = @_;

    my $appid = $self->appid;
    my $pid = $self->pids->{route_table};
    $self->set_header( 'Content-Length' => '0', );
    my $resp = $self->put(
        "/oamp/configuration/objects/RouteTable/$pid/provisions/Cached?appid=$appid&sync_key=0",
    );
    return $resp;
}

sub download_channel_groups {
    my ($self) = @_;

    my $appid = $self->appid;
    my $pid = $self->pids->{channel_group_collection};
    $self->set_header( 'Content-Length' => '0', );
    my $resp = $self->put(
        "/oamp/configuration/objects/ChannelGroups/$pid/provisions/Cached?appid=$appid&sync_key=0",
    );
    return $resp;
}

#delete all children of bn2020 but not the node itself
sub delete_all_bn2020 {
    my ($self) = @_;

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
    for (my $i = 0; $i < 100; $i++) { # 500 seconds on 5 seconds timeout
        $resp = $self->get("/");
        last if $resp->code < 400;
    }
    return $resp;
}

# warning: does create a lot of open transactions without deleting them.
# see the scriptfile for an example how to generate documentation of this
sub build_documentation {
    my ($self) = @_;
    my $classinfo = $self->classinfo;
    for my $class (keys %{ $classinfo }) {    
        my $classname = $classinfo->{$class}{name};
        my $appid = $self->appid;
        my $pid = 10_000;
        my $resp  = $self->get(
            "/oamp/configuration/objects/$classname/NULL?detaillevel=4&pid=$pid&appid=$appid",
        );
        if ($resp->code != 200) {
            warn "$class: couldn't fetch info\n";
            next;
        }
        my $data = $resp->data;
        my $options = [];
        for my $p ( keys %{ $data->{property} } ) {
            next if lc($data->{property}{$p}{type}) ne "configure";
            my @choices;
            if ($data->{property}{$p}{choiceset}{choice} &&
                ref $data->{property}{$p}{choiceset}{choice} eq "ARRAY") {
                for my $v (@{ $data->{property}{$p}{choiceset}{choice} }) {
                    push @choices, $v->{value} =~ s/^value\((.*)\)$/$1/r;
                }
            }
            push @{ $options }, {
                name => $p,
                default => $data->{property}{$p}{value},
                displayname => $data->{property}{$p}{displayname},
                @choices ? (choices => [@choices]) : (),
            };
        }
        $classinfo->{$class}{options} = $options;
    }
    return $classinfo;
}

sub _build_response_data {
    my ( $self, $req, $pid, $options ) = @_;
    my $resp = {
        pid      => $pid,
        property => {},
    };
    for my $p ( keys %{ $req->{property} } ) {
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
                'MediaMode'           => { 'configuredvalue' => 'Audio Dynamic Density Management' },
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
