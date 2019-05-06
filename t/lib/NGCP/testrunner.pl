use lib '..';
use strict;
use warnings;
use NGCP::TestFramework;

my $server = $ARGV[0] || undef;
my $selected = $ARGV[1] || 'all';

if ( !$server ){
    print "Usage: \$ perl testrunner.pl [<testsystem>] [<testset>]\n";
    print "Usage example: \$ perl testrunner.pl 192.168.88.162\n";
    print "Usage example: \$ perl testrunner.pl 192.168.88.162 fast\n";
    print "Possible test set: all, stable, fast, t/lib/NGCP/TestFramework/Interface/Contracts.yaml\n";
    print "Default test set: all\n";
    exit(1);
}

if ( $selected eq 'stable' ) {
    print "Test selection: $selected\n";
}
elsif ( $selected eq 'fast' ) {
    print "Test selection: $selected\n";
}
elsif ( $selected eq 'all' ) {
    print "Test selection: all\n";
}
else{
    print "Test selection: $selected\n";
}

print "################################################################################\n";
print "Finished main setup, now running tests ...\n";

$ENV{CATALYST_SERVER_SUB}="https://$server:443";
$ENV{CATALYST_SERVER}="https://$server:1443";
$ENV{NGCP_SESSION_ID}=int(rand(1000)).time;

my $test_framework = NGCP::TestFramework->new( {file_path => $selected} );

my $result_code = $test_framework->run();

print "Finished test execution, test execution returned with exit code $result_code.\n";

1;
