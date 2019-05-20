#use forks;
use warnings;
use strict;
use threads;
use Selenium::Collection::testfunctions;

my $thread1 = threads->create(sub {
    ctr_admin();
} );
my $thread2 = threads->create(sub {
    ctr_domain();
} );
my $thread3 = threads->create(sub {
    ctr_billing();
} );
my $thread4 = threads->create(sub {
    ctr_customer();
} );

my $test1 = $thread1->join;
my $test2 = $thread2->join;
my $test3 = $thread3->join;
my $test4 = $thread4->join;

=pod
while($thread1->is_running() && $thread2->is_running() && $thread3->is_running() && $thread4->is_running()) {
  sleep(5);
}
=cut

print "----------------------------------------------\n";

ok($test1, "Admin Test was executed till the end");

ok($test2, "Domain Test was executed till the end");

ok($test3, "Billing Test was executed till the end");

ok($test4, "Customer Test was executed till the end");

print "----------------------------------------------\n";

$test1 = 0;
$test2 = 0;
$test3 = 0;
$test4 = 0;

$thread1 = threads->create(sub {
    ctr_peering();
} );
$thread2 = threads->create(sub {
    ctr_reseller();
} );
$thread3 = threads->create(sub {
    ctr_rw_ruleset();
} );
$thread4 = threads->create(sub {
    ctr_subscriber();
} );

$test1 = $thread1->join;
$test2 = $thread2->join;
$test3 = $thread3->join;
$test4 = $thread4->join;

=pod
while($thread1->is_running() && $thread2->is_running() && $thread3->is_running() && $thread4->is_running()) {
  sleep(5);
}
=cut

print "----------------------------------------------\n";

ok($thread1, "Peering Test was executed till the end");

ok($thread2, "Reseller Test was executed till the end");

ok($thread3, "RW Ruleset Test was executed till the end" );

ok($thread4, "Subscriber Test was executed till the end");

print "----------------------------------------------\n";

donetest();

=pod
ctr_admin();
ctr_billing();
ctr_customer();
ctr_domain();
=cut



