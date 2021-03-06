use NGCP::Panel::Utils::DialogicImg;

use strict;
use warnings;
use DDP;
use Data::Dumper;

exit if try_parse_file(@ARGV);

my $resp;

my $test = NGCP::Panel::Utils::DialogicImg->new(
    server      => 'https://10.15.20.149',
);

p $test->login( 'dialogic', 'Dial0gic' );

$resp = $test->obtain_lock();
p $resp->code;

print "LOGGED IN, LOCK OBTAINED ############################\n";

my $result = $test->create_all_sipsip({
    ip_sip => '10.15.21.92',
    ip_rtp => '10.15.22.11',
    ip_client => '10.15.20.144',
    in_codecs => ['G711 ulaw', 'G711 alaw', 'G729', 'AMR'],
    out_codecs => ['G711 ulaw', 'G711 alaw', 'G729', 'AMR'],
    ss7_opc => '1-1-1',
    ss7_apc => '2-2-2',  # adjacent point code
    ss7_dpc => '2-2-2',
    ip_nfs_server => '192.168.51.45',
    nfs_path => '//export/users/dialogic2',
    snmp_system_name => 'Dialogic2',
    snmp_system_location => 'foobar',
    snmp_system_contact => 'foobar',
    snmp_community_name => 'bar',
    use_optical_spans => 1,
    is_isdn_userside => 1,
    },
    2,
    );

exit;


# $resp = $test->delete_all_bn2020;
# $resp = $test->delete_all_bn2020;
# p $resp->code;
# exit 0;

# $resp = $test->reboot_and_wait;
# p $resp;
# sleep 2;
# exit;
# print "login again\n";
# p $test->login( 'dialogic', 'Dial0gic' );
# $resp = $test->get( '/oamp/configuration/objects', { appid => $test->appid } );
# $resp = $test->obtain_lock();
# p $resp->code;

# print_documentation_md($test);

# $resp = $test->get_config;
# p $resp;
# #p $test->classinfo;
# exit;

# $test->pids->{facility} = 10008;
# $resp = $test->create_ds1_spans;
# p $resp;
# p $resp->data;
# exit;


sub print_documentation_md {
    my ($api) = @_;
    my $classinfo = $api->build_documentation;
    for my $class (keys %{ $classinfo }) {
        my $parent = $classinfo->{$class}{parent};
        my $options = $classinfo->{$class}{options};
        print "\n#$class\n\n";
        print "This is a child of `$parent`\n\n";
        print "## Options\n\n";
        print "Name|Description|Default|Alternatives\n";
        print "----|-----------|-------|------------\n";
        for my $o (@{ $options }) {
            my ( $name, $displayname, $default, $choices )
                = @{$o}{ 'name', 'displayname', 'default', 'choices' };
            my $choices_str = $choices && @{$choices}
                            ? join( ", ", map {"`$_`"} @{$choices} ) : '';
            if ($default) {
                $default = "`$default`";
            }
            print "`$name` | $displayname | $default | $choices_str \n";
        }
    }
    return;
}

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
