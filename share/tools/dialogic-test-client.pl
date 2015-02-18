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
