use NGCP::Panel::Utils::DialogicImg;

use strict;
use warnings;
use DDP;
use Data::Dumper;

exit if try_parse_file(@ARGV);

my $test = NGCP::Panel::Utils::DialogicImg->new(
    server      => 'https://10.15.20.150',
    clientattrs => { 
    	timeout => 5,
    	# SSL_options => {
    	# 	SSL_version => 'SSLv23:!SSLv2:!SSLv3:!TLSv1_1:!TLSv1_2',
    	# },
	},
);

#p $test;

p $test->login( 'dialogic', 'Dial0gic' );

my $resp
    = $test->get( '/oamp/configuration/objects', { appid => $test->appid } );

$resp = $test->obtain_lock();
p $resp->code;

print "LOGGED IN, LOCK OBTAINED ############################\n";

# $resp = $test->delete_all_bn2020;
# p $resp;
# exit 0;

# $resp = $test->reboot_and_wait;
# p $resp;
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
		NIIPAddress => '11.2.3.4',
		NIIPPhy => 'Services',
	});
p $resp->code;
#p $resp->data;

$resp = $test->create_interface;  # DataA by default
p $resp->code;
#p $resp->data;

$resp = $test->create_ip_address({NIIPAddress => '11.6.7.8',
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
	ChannelCount => 5, # our licence has 128 or so
	});
p $resp->code;
#p $resp->data;

print "CREATE SIGNALING ###################################\n";

$resp = $test->create_signaling({});
p $resp->code;
#p $resp->data;

print "CREATE SIP ###################################\n";

$resp = $test->create_sip;
p $resp->code;
#p $resp->data;

print "CREATE SIP IP ###################################\n";

$resp = $test->create_sip_ip;
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

print "CREATE SIP PROFILE COLLECTION ###################################\n";

$resp = $test->create_sip_profile_collection;
p $resp->code;
#p $resp->data;

print "CREATE SIP PROFILE ###################################\n";

$resp = $test->create_sip_profile({
	});
p $resp->code;
#p $resp->data;

$resp = $test->create_sip_profile({
	});
p $resp->code;
#p $resp->data;

print "DOWNLOAD PROFILE COLLECTION ###################################\n";

$resp = $test->download_profiles;
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

print "CREATE CHANNEL GROUP ###################################\n";

$resp = $test->create_channel_group({
	SignalingType => 'SIP',
	});
p $resp->code;
#p $resp->data;


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
