use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is diag)];
use Selenium::Remote::Driver::Extensions qw();

diag("Init");
my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
my $d = Selenium::Remote::Driver::Extensions->new (
    'browser_name' => $browsername,
    'proxy' => {'proxyType' => 'system'} );

$d->login_ok();

diag("Done: admin-login.t");
done_testing;
# vim: filetype=perl
