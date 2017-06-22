use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is diag ok)];
use Selenium::Remote::Driver::Extensions qw();
use Selenium::Firefox qw();

diag("Init");
my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
my $d = Selenium::Firefox->new (
    'browser_name' => $browsername,
    accept_ssl_certs => 1,
    extra_capabilities => {
        acceptInsecureCerts => \1,
        },
    # 'proxy' => {'proxyType' => 'system'},
    # error_handler => sub { print $_[1]; print "\ngoodbye"; },
);

#use DDP use_prototypes=>0; p "instatiation done";
#p $d->binary_mode;

# $d->login_ok();

#### POC DO LOGIN

# $d->set_implicit_wait_timeout(10_000);
$d->set_timeout("implicit", 10000);
$d->set_timeout("page load", 10000);

    diag("Loading login page (logout first)");
    my $uri = $ENV{CATALYST_SERVER} || 'https://10.15.17.196:1443';
    diag("Loading " . "$uri/logout");
    $d->get("$uri/logout"); # make sure we are logged out
    $d->get("$uri/login");

    diag("Do Admin Login");
    # $d->find_text("Admin Sign In");
    ok($d->find_element("//*[contains(text(),\"Admin Sign In\")]"), "Found Text Admin Sign In");
    is($d->get_title, '');
    $d->find_element('id("username")')->send_keys('administrator');
    $d->find_element('id("password")')->send_keys('administrator');
    $d->find_element('id("submit")')->click();

    diag("Checking Admin interface");
    is($d->get_title, 'Dashboard');
    is($d->find_element('//*[@id="masthead"]//h2')->get_text(), "Dashboard");
    ok(1, "Login Successful");


#################

diag("Done: admin-login.t");
done_testing;
# vim: filetype=perl
