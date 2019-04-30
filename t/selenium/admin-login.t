use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is diag ok)];
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

ok(1, "Instantiation ok");

$c->login_ok();

diag("Done: admin-login.t");
done_testing;
# vim: filetype=perl
