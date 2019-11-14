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

if(!admin_login()) {
    print "-------------------------------------\n";
    print "Test was aborted. Login failed\n";
    print $ENV{CATALYST_SERVER} . "\n";
    print "-------------------------------------\n";
    exit 1;
}

if($testplan eq $dir . 'runner.t') {
    @tests = (
        $dir . 'controller_admin.t',
        $dir . 'controller_billing.t',
        $dir . 'controller_customer.t',
        $dir . 'controller_domain.t',
        $dir . 'controller_emergency.t',
        $dir . 'controller_header.t',
        $dir . 'controller_invoice.t',
        $dir . 'controller_ncos.t',
        $dir . 'controller_other.t',
        $dir . 'controller_peering.t',
        $dir . 'controller_profilepackage.t',
        $dir . 'controller_profileset.t',
        $dir . 'controller_reseller.t',
        $dir . 'controller_rw_ruleset.t',
        $dir . 'controller_soundset.t',
        $dir . 'controller_subscriber.t',
        $dir . 'controller_terminate.t',
        $dir . 'controller_timeset.t',
        );

} elsif($testplan eq 'exp') {
    @tests = (
        $dir . 'controller_admin.t',
        $dir . 'controller_billing.t',
        $dir . 'controller_customer.t',
        $dir . 'controller_domain.t',
        $dir . 'controller_emergency.t',
        $dir . 'controller_header.t',
        $dir . 'controller_invoice.t',
        $dir . 'controller_ncos.t',
        $dir . 'controller_other.t',
        $dir . 'controller_peering.t',
        $dir . 'controller_profilepackage.t',
        $dir . 'controller_profileset.t',
        $dir . 'controller_reseller.t',
        $dir . 'controller_rw_ruleset.t',
        $dir . 'controller_soundset.t',
        $dir . 'controller_subscriber.t',
        $dir . 'controller_terminate.t',
        $dir . 'controller_timeset.t',
        );

} else {
    if (index($testplan, $dir . 'controller_admin.t') != -1 || index($testplan, $dir . 'admin') != -1) {
        $string = $dir . 'controller_admin.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_billing.t') != -1 || index($testplan, $dir . 'billing') != -1) {
        $string = $dir . 'controller_billing.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_customer.t') != -1 || index($testplan, $dir . 'customer') != -1) {
        $string = $dir . 'controller_customer.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_domain.t') != -1 || index($testplan, $dir . 'domain') != -1) {
        $string = $dir . 'controller_domain.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_emergency.t') != -1 || index($testplan, $dir . 'emergency') != -1) {
        $string = $dir . 'controller_emergency.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_header.t') != -1 || index($testplan, $dir . 'header') != -1) {
        $string = $dir . 'controller_header.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_invoice.t') != -1 || index($testplan, $dir . 'invoice') != -1) {
        $string = $dir . 'controller_invoice.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_ncos.t') != -1 || index($testplan, $dir . 'ncos') != -1) {
        $string = $dir . 'controller_ncos.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_other.t') != -1 || index($testplan, $dir . 'other') != -1) {
        $string = $dir . 'controller_other.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_peering.t') != -1 || index($testplan, $dir . 'peering') != -1) {
        $string = $dir . 'controller_peering.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_profilepackage.t') != -1 || index($testplan, $dir . 'profilepackage') != -1) {
        $string = $dir . 'controller_profilepackage.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_profileset.t') != -1 || index($testplan, $dir . 'profileset') != -1) {
        $string = $dir . 'controller_profileset.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_reseller.t') != -1 || index($testplan, $dir . 'reseller') != -1) {
        $string = $dir . 'controller_reseller.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_rw_ruleset.t') != -1 || index($testplan, $dir . 'rw_ruleset') != -1) {
        $string = $dir . 'controller_rw_ruleset.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_soundset.t') != -1 || index($testplan, $dir . 'soundset') != -1) {
        $string = $dir . 'controller_soundset.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_subscriber.t') != -1 || index($testplan, $dir . 'subscriber') != -1) {
        $string = $dir . 'controller_subscriber.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_terminate.t') != -1 || index($testplan, $dir . 'terminate') != -1) {
        $string = $dir . 'controller_terminate.t';
        push @tests, $string;
    };
    if (index($testplan, $dir . 'controller_timeset.t') != -1 || index($testplan, $dir . 'timeset') != -1) {
        $string = $dir . 'controller_timeset.t';
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
        'timer', '1',
        );
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
        'jobs', '4',
        );
    my $harness = TAP::Harness->new( \%args );
    $harness->runtests(@tests);
    print "\n";
};