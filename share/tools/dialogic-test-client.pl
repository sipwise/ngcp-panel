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

p $test;

p $test->login( 'dialogic', 'Dial0gic' );

my $resp
    = $test->get( '/oamp/configuration/objects', { appid => $test->appid } );

$resp = $test->obtain_lock();
p $resp;

print "LOGGED IN, LOCK OBTAINED ############################\n";

# $resp
#     = $test->get(
#     '/oamp/configuration/objects/Node/NULL?detaillevel=1&pid=10000&appid='
#         . $test->appid );
# p $resp;
# #p $resp->data;

# print "GOT DATA, SEND NOW ###################################\n";

# $resp
#     = $test->post(
#     '/oamp/configuration/objects/Node/NULL?detaillevel=1&pid=10000&appid='
#         . $test->appid, $resp->data );
# p $resp;
# #p $resp->data;

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
		NIIPAddress => '10.2.3.4',
		NIIPPhy => 'Services',
	});
p $resp->code;
#p $resp->data;

$resp = $test->create_interface;  # DataA
p $resp->code;
#p $resp->data;

$resp = $test->create_ip_address({NIIPAddress => '10.6.7.8',
	NIIPPhy => 'Media 0'});
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
