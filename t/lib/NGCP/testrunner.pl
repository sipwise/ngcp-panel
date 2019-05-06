use lib '..';
use strict;
use warnings;
use NGCP::TestFramework;
use Test::More;
use threads;
use Thread::Queue;
use Data::Dumper;

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

my @test_files;

if ( $selected eq 'stable' ) {
    print "Test selection: stable\n";
}
elsif ( $selected eq 'fast' ) {
    print "Test selection: fast\n";
}
elsif ( $selected eq 'all' ) {
    print "Test selection: all\n";
    map { push @test_files, "TestFramework/Interface/$_" } `ls TestFramework/Interface`;
}
else{
    print "Test selection: $selected\n";
    push @test_files, $selected;
}

print "################################################################################\n";
print "Finished main setup, now running tests ...\n";

$ENV{CATALYST_SERVER_SUB}="https://$server:443";
$ENV{CATALYST_SERVER}="https://$server:1443";
$ENV{NGCP_SESSION_ID}=int(rand(1000)).time;

my @threads;
my $tests_queue = Thread::Queue->new();

for ( @test_files ) {
    $tests_queue->enqueue($_);
}

$tests_queue->end();

for (1..2) {
    push @threads, threads->create( {'context' => 'void'}, \&worker, $tests_queue );
}

foreach ( @threads ){
  $_->join();
}

done_testing();

sub worker {
    my ($tests_queue) = @_;

    while ( my $test_file = $tests_queue->dequeue_nb() ) {
        my $start_time = time;
        print "Running tests from $test_file\n";
        my $test_framework = NGCP::TestFramework->new( {file_path => $test_file} );

        my $result_code = $test_framework->run();

        my $total_time = time - $start_time;
        print "Finished test execution for $test_file, test execution returned with exit code $result_code.\n";
        print "Tests for $test_file took $total_time seconds.\n";
    }
}

1;
