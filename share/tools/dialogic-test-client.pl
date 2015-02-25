use NGCP::Panel::Utils::DialogicImg;

use strict;
use warnings;
use DDP;
use Data::Dumper;

exit if try_parse_file(@ARGV);

my $test = NGCP::Panel::Utils::DialogicImg->new(
    server      => 'https://10.15.20.150',
);

p $test->login( 'dialogic', 'Dial0gic' );

my $resp
    = $test->get( '/oamp/configuration/objects', { appid => $test->appid } );

$resp = $test->obtain_lock();
p $resp->code;

print "LOGGED IN, LOCK OBTAINED ############################\n";

# $resp = $test->delete_all_bn2020;
# $resp = $test->delete_all_bn2020;
# p $resp->code;
# exit 0;

# $resp = $test->reboot_and_wait;
# p $resp;
# exit 0;

# $test->pids->{route_table} = 10033;
# $test->download_route_table;
# $test->pids->{channel_group_collection} = 10030;
# $test->download_channel_groups;
# exit 0;
# $resp = $test->create_route_element({
# 	StringType => 'Channel Group',
# 	InChannelGroup => 'ChannelGroup0',
# 	RouteActionType => 'Channel Group',
# 	RouteActionList => 'ChannelGroup0',
# 	});
# p $resp->code;
# #p $resp->data;
# exit 0;

$resp = $test->create_bn2020;
p $resp->code;
#p $resp->data;


print "CREATE NETWORK ###################################\n";

$resp = $test->create_network;
p $resp->code;
#p $resp->data;

print "CREATE INTERFACE COLLECTION ###################################\n";

$resp = $test->create_interface_collection;
p $resp->code;
#p $resp->data;

print "CREATE INTERFACE ###################################\n";

$resp = $test->create_interface;  # Control by default
p $resp->code;
#p $resp->data;

$resp = $test->create_ip_address({
		NIIPAddress => '10.15.20.92',
		NIIPPhy => 'Services',
	});
p $resp->code;
#p $resp->data;

$resp = $test->create_interface;  # DataA by default
p $resp->code;
#p $resp->data;

$resp = $test->create_ip_address({
		NIIPAddress => '10.15.21.10',
		NIIPPhy => 'Media 0'});
p $resp->code;
#p $resp->data;

print "CREATE FACILITY ###################################\n";

$resp = $test->create_facility;
p $resp->code;
#p $resp->data;

print "CREATE PACKET FACILITY COLLECTION ###################################\n";

$resp = $test->create_packet_facility_collection;
p $resp->code;
#p $resp->data;

print "CREATE PACKET FACILITY ###################################\n";

$resp = $test->create_packet_facility({
	ChannelCount => 50, # our licence has 128 or so
	});
p $resp->code;
#p $resp->data;

lsign:

print "CREATE SIGNALING ###################################\n";

$resp = $test->create_signaling;
p $resp->code;
#p $resp->data;

print "CREATE SIP ###################################\n";

$resp = $test->create_sip;
p $resp->code;
#p $resp->data;

print "CREATE SIP IP ###################################\n";

$resp = $test->create_sip_ip({
	IPAddress => '10.15.20.92',
	});
p $resp->code;
#p $resp->data;

print "CREATE PROFILE COLLECTION ###################################\n";

$resp = $test->create_profile_collection;
p $resp->code;
#p $resp->data;

print "CREATE IP PROFILE COLLECTION ###################################\n";

$resp = $test->create_ip_profile_collection;
p $resp->code;
#p $resp->data;

print "CREATE IP PROFILE ###################################\n";

$resp = $test->create_ip_profile({
	DigitRelay => 'DTMF Packetized',
	});
p $resp->code;
#p $resp->data;

print "CREATE VOCODER PROFILE ###################################\n";

$resp = $test->create_vocoder_profile({
	PayloadType => 'G711 ulaw',
	});
p $resp->code;
#p $resp->data;

$resp = $test->create_vocoder_profile({
	PayloadType => 'G711 alaw',#G711 (u/a)law, G729, G722, AMR, ...
	});
p $resp->code;
#p $resp->data;

$resp = $test->create_vocoder_profile({
	PayloadType => 'G729',
	});
p $resp->code;
#p $resp->data;

$resp = $test->create_vocoder_profile({
	PayloadType => 'AMR',
	});
p $resp->code;
#p $resp->data;

print "CREATE SIP PROFILE COLLECTION ###################################\n";

$resp = $test->create_sip_profile_collection;
p $resp->code;
#p $resp->data;

print "CREATE SIP PROFILE ###################################\n";

$resp = $test->create_sip_profile({
	});
p $resp->code;
#p $resp->data;

# $resp = $test->create_sip_profile({
# 	});
# p $resp->code;
# #p $resp->data;

print "DOWNLOAD PROFILE COLLECTION ###################################\n";

$resp = $test->download_profiles;
p $resp->code;
#p $resp->data;

print "CREATE EXTERNAL NETWORK ELEMENTS ###################################\n";

$resp = $test->create_external_network_elements;
p $resp->code;
#p $resp->data;

print "CREATE EXTERNAL GATEWAY COLLECTION ###################################\n";

$resp = $test->create_external_gateway_collection;
p $resp->code;
#p $resp->data;

print "CREATE EXTERNAL GATEWAY ###################################\n";

$resp = $test->create_external_gateway({
	Name => 'Phone1',
	IPAddress => '10.15.20.199',
	IPAddress4 => '10.15.20.199',
	});
p $resp->code;
#p $resp->data;

print "CREATE ROUTING CONFIGURATION ###################################\n";

$resp = $test->create_routing_configuration({
	});
p $resp->code;
#p $resp->data;

print "CREATE CHANNEL GROUP COLLECTION ###################################\n";

$resp = $test->create_channel_group_collection({
	});
p $resp->code;
#p $resp->data;

print "CREATE ROUTE TABLE COLLECTION ###################################\n";

$resp = $test->create_route_table_collection;
p $resp->code;
#p $resp->data;

print "CREATE ROUTE TABLE ###################################\n";

$resp = $test->create_route_table({
	#Name => 'ngcp_route_table',
	});
p $resp->code;
#p $resp->data;

print "CREATE CHANNEL GROUP ###################################\n";

$resp = $test->create_channel_group({
	SignalingType => 'SIP',
	#RouteTable => ???,
	InRouteTable => 'Table - ID: 5',
	InIPProfile => 'IP_Profile_1',
	InIPProfileId => '1',
	OutIPProfile => 'IP_Profile_1',
	#incoming ip profile, set?
	#outgoing ip profile, set?
	SupportA2F => 'True',
	});
p $resp->code;
#p $resp->data;

print "CREATE NETWORK ELEMENT (CG) ###################################\n";

$resp = $test->create_cg_network_element;
p $resp->code;
#p $resp->data;

print "CREATE NODE ASSOCIATION ###################################\n";

$resp = $test->create_node_association;
p $resp->code;
#p $resp->data;

print "CREATE ROUTE ELEMENT ###################################\n";

$resp = $test->create_route_element({
	StringType => 'Channel Group',
	InChannelGroup => 'ChannelGroup0',
	RouteActionType => 'Channel Group',
	RouteActionList => 'ChannelGroup0',
	});
p $resp->code;
#p $resp->data;

$resp = $test->download_route_table;
p $resp->code;

$resp = $test->download_channel_groups;
p $resp->code;


sub try_parse_file {
	return unless ($#ARGV >= 1);

	print "parsing $ARGV[0]\n";
	use Data::Serializer::Raw;
	my $s = Data::Serializer::Raw->new(serializer => 'XML::Simple');
	print Dumper $s->retrieve($ARGV[0]);
	print "\n";
	return 1;
}

1;
