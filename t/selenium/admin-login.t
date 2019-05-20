use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is diag ok)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;


sub admin_login {
    my ($port) = @_;
    return unless $port;

    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
        },
        port => $port
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    $c->login_ok();
}

if(! caller) {
    admin_login();
    done_testing;
}

1;
# vim: filetype=perl
