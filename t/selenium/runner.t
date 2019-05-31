use warnings;
use strict;

use lib 't/lib';
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use TAP::Harness;

require "/code/t/selenium/admin_login.t";

my $jenkins = $ENV{JENKINS};
my $testplan = $ENV{TESTFILES};
my $dir = 't/selenium/';
my @tests;
my $string;

if(admin_login()) {
    print "-----------------------------------------\n";
    print "Login was succesfull. Launching Test Plan\n";
    print $ENV{CATALYST_SERVER} . "\n";
    print "-----------------------------------------\n";
} else {
    print "-------------------------------------\n";
    print "Test was aborted. Login failed\n";
    print $ENV{CATALYST_SERVER} . "\n";
    print "-------------------------------------\n";
    exit 1;
}

if($testplan eq $dir . 'runner.t') {
    @tests = ($dir . 'controller_admin.t', $dir . 'controller_billing.t', $dir . 'controller_customer.t', $dir . 'controller_domain.t', $dir . 'controller_peering.t', $dir . 'controller_reseller.t', $dir . 'controller_rw_ruleset.t', $dir . 'controller_subscriber.t');
} else {
    if (index($testplan, $dir . 'controller_admin.t') != -1) {
        $string = $dir . 'controller_admin.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_billing.t') != -1) {
        $string = $dir . 'controller_billing.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_customer.t') != -1) {
        $string = $dir . 'controller_customer.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_domain.t') != -1) {
        $string = $dir . 'controller_domain.t';
        push @tests, $string;
    };
=pod
    if (index($testplan, $dir . 'controller_ncos.t') != -1) {
        $string = $dir . 'controller_ncos.t';
        push @tests, $string;
    };
=cut
    if (index($testplan, $dir . 'controller_peering.t') != -1) {
        $string = $dir . 'controller_peering.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_reseller.t') != -1) {
        $string = $dir . 'controller_reseller.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_rw_ruleset.t') != -1) {
        $string = $dir . 'controller_rw_ruleset.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_subscriber.t') != -1) {
        $string = $dir . 'controller_subscriber.t';
        push @tests, $string;
    };
};

if($jenkins) {
    my %args = ('lib', 't/lib',
        'merge', '1',
        'comments', '1',
        'failures', '1',
        'verbosity', '0',
        'formatter_class', 'TAP::Formatter::JUnit',
        'jobs', '4',
        'timer', '1');
    my $harness = TAP::Harness->new( \%args );
    $harness->runtests(@tests);
    print "\n";

} else {
    my %args = ('lib', 't/lib',
        'comments', '1',
        'failures', '1',
        'formatter_class', 'TAP::Formatter::Console',
        'verbosity', '0',
        'color', '1',
        'jobs', '4');
    my $harness = TAP::Harness->new( \%args );
    $harness->runtests(@tests);
    print "\n";
};