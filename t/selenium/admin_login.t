use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is diag ok)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use TryCatch;

sub admin_login {
    my ($port) = @_;
    $port = '4444' unless $port;

    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
        },
        port => $port
    );
    try {
        my $login = 'administrator';
        my $pwd = 'administrator';
        my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
        $d->get("$uri/logout"); # make sure we are logged out
        $d->get("$uri/login");
        $d->find_element('#username', 'css')->send_keys($login);
        $d->find_element('#password', 'css')->send_keys($pwd);
        $d->find_element('#submit', 'css')->click();
        return 1;
    }
    catch {
        return 0;
    };
}

if(! caller) {
    admin_login();
    done_testing;
}

1;
# vim: filetype=perl
