use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
);

my $c = Selenium::Collection::Common->new(
    driver => $d
);

$d->login_ok();

my $resellername = ("test" . int(rand(10000)));
my $contractid = ("test" . int(rand(10000)));
my $rulesetname = ("rule" . int(rand(10000)));

$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

$c->create_rw_ruleset($resellername, $rulesetname);
$c->delete_rw_ruleset($rulesetname);

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

done_testing;