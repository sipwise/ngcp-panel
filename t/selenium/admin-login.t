use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is diag ok)];
use Selenium::Remote::Driver::FirefoxExtensions;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
    version => '56.0',
    platform => 'linux',
    accept_ssl_certs => 1,
);

ok(1, "Instantiation ok");

$d->login_ok();

diag("Done: admin-login.t");
done_testing;
# vim: filetype=perl
