use warnings;
use strict;
use threads;
use TAP::Harness;
require "/code/t/selenium/admin-login.t";
require "/code/t/selenium/controller_admin.t";
require "/code/t/selenium/controller_billing.t";
require "/code/t/selenium/controller_customer.t";
require "/code/t/selenium/controller_domain.t";
require "/code/t/selenium/controller_peering.t";
require "/code/t/selenium/controller_reseller.t";
require "/code/t/selenium/controller_rw_ruleset.t";
require "/code/t/selenium/controller_subscriber.t";

my $jenkins = $ENV{JENKINS};

if($jenkins) {
    my $dir = 't/selenium/';
    my %args = ('lib', 't/lib',
        'formatter_class', 'TAP::Formatter::JUnit',
        'merge', '1',
        'comments', '1',
        'failures', '1',
        'verbosity', '1',
        'jobs', '4',
        'timer', '1');
    my @tests = ($dir . 'controller_admin.t', $dir . 'controller_billing.t', $dir . 'controller_customer.t', $dir . 'controller_domain.t');
    my $harness = TAP::Harness->new( \%args );
    $harness->runtests(@tests);

} else {
    my $dir = 't/selenium/';
    my %args = ('lib', 't/lib',
        'comments', '1',
        'failures', '1',
        'verbosity', '1',
        'color', '1',
        'jobs', '4');
    my @tests = ($dir . 'controller_admin.t', $dir . 'controller_billing.t', $dir . 'controller_customer.t', $dir . 'controller_domain.t');
    my $harness = TAP::Harness->new( \%args );
    $harness->runtests(@tests);
}

=pod
my $thread1 = threads->create(sub {
    admin_login('4444');
} );

my $logintest = $thread1->join;

if(! ok($logintest, "Login was successfull. Server is here")) {
    done_testing();
    exit;
}

$thread1 = threads->create(sub {
    ctr_admin('4444');
} );
my $thread2 = threads->create(sub {
    ctr_billing('5555');
} );
my $thread3 = threads->create(sub {
    ctr_customer('6666');
} );
my $thread4 = threads->create(sub {
    ctr_domain('7777');
} );

my $test1 = $thread1;
my $test2 = $thread2;
my $test3 = $thread3;
my $test4 = $thread4;

my $thread1done = 1;
my $thread2done = 1;
my $thread3done = 1;
my $thread4done = 1;

while ($thread1->is_running() || $thread2->is_running() || $thread3->is_running() || $thread4->is_running()) {
    if($thread1->is_joinable() && $thread1done) {
        $thread1done = 0;
        $test1 = $thread1->join;
        $thread1 = threads->create(sub {
            ctr_peering('4444');
        } );
    }
    if($thread2->is_joinable() && $thread2done) {
        $thread2done = 0;
        $test2 = $thread2->join;
        $thread2 = threads->create(sub {
            ctr_reseller('5555');
        } );
    }
    if($thread3->is_joinable() && $thread3done) {
        $thread3done = 0;
        $test3 = $thread3->join;
        $thread3 = threads->create(sub {
            ctr_rw_ruleset('6666');
        } );
    }
    if($thread4->is_joinable() && $thread4done) {
        $thread4done = 0;
        $test4 = $thread4->join;
        $thread4 = threads->create(sub {
            ctr_subscriber('7777');
        } );
    }
}

my $test5 = $thread1->join;
my $test6 = $thread2->join;
my $test7 = $thread3->join;
my $test8 = $thread4->join;

print "----------------------------------------------\n";

ok($test1, "Admin Test was executed till the end");

ok($test2, "Billing Test was executed till the end");

ok($test3, "Customer Test was executed till the end");

ok($test4, "Domain Test was executed till the end");

ok($test5, "Peering Test was executed till the end");

ok($test6, "Reseller Test was executed till the end");

ok($test7, "RW Ruleset Test was executed till the end" );

ok($test8, "Subscriber Test was executed till the end");

print "----------------------------------------------\n";
=cut
done_testing();
