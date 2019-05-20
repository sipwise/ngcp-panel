use warnings;
use strict;
use threads;
require "/code/t/selenium/admin-login.t";
require "/code/t/selenium/controller_admin.t";
require "/code/t/selenium/controller_billing.t";
require "/code/t/selenium/controller_customer.t";
require "/code/t/selenium/controller_domain.t";
require "/code/t/selenium/controller_peering.t";
require "/code/t/selenium/controller_reseller.t";
require "/code/t/selenium/controller_rw_ruleset.t";
require "/code/t/selenium/controller_subscriber.t";

my $thread1 = threads->create(sub {
    admin_login();
} );

my $logintest = $thread1->join;

if(! ok($logintest, "Login was successfull. Server is here")) {
    done_testing();
    exit;
}

$thread1 = threads->create(sub {
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

$thread1 = threads->create(sub {
    ctr_subscriber();
} );
$thread2 = threads->create(sub {
    ctr_reseller();
} );
$thread3 = threads->create(sub {
    ctr_rw_ruleset();
} );
$thread4 = threads->create(sub {
    ctr_peering();
} );

my $test5 = $thread1->join;
my $test6 = $thread2->join;
my $test7 = $thread3->join;
my $test8 = $thread4->join;

print "----------------------------------------------\n";

ok($test1, "Admin Test was executed till the end");

ok($test3, "Billing Test was executed till the end");

ok($test4, "Customer Test was executed till the end");

ok($test2, "Domain Test was executed till the end");

ok($test8, "Peering Test was executed till the end");

ok($test6, "Reseller Test was executed till the end");

ok($test7, "RW Ruleset Test was executed till the end" );

ok($test5, "Subscriber Test was executed till the end");

print "----------------------------------------------\n";

done_testing();
