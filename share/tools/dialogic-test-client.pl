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

my $result = $test->create_all_sipsip({
    ip1 => '10.15.20.92',
    ip2 => '10.15.21.10',
    ip_client => '10.15.20.199',
    in_codecs => ['G711 ulaw', 'G711 alaw', 'G729', 'AMR'],
    out_codecs => ['G711 ulaw', 'G711 alaw', 'G729', 'AMR'],
    },
    2,
    );

exit;


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
