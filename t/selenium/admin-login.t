use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is diag ok)];
use Selenium::Remote::Driver::FirefoxExtensions;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    remote_server_addr => '127.0.0.1',
    port => '4444',
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
    proxy => {proxyType => 'system'},
);

ok(1, "Instantiation ok");

$d->login_ok();

diag("Done: admin-login.t");
done_testing;
# vim: filetype=perl
