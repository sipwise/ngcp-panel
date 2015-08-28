use lib 't/lib';
use Test::More import => [qw(done_testing is diag)];
use Selenium::Remote::Driver::Extensions qw();

diag("Init");
my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
my $d = Selenium::Remote::Driver::Extensions->new (
    'browser_name' => $browsername,
    'proxy' => {'proxyType' => 'system'} );

diag("Loading login page (logout first)");
$d->set_window_size(1024,1280) if ($browsername ne "htmlunit");
$d->get("$uri/logout"); # make sure we are logged out
$d->get("$uri/login");
$d->set_implicit_wait_timeout(10000);
$d->default_finder('xpath');

diag("Do Admin Login");
$d->find_text("Admin Sign In");
is($d->get_title, '');
$d->find_element('username', name)->send_keys('administrator');
$d->find_element('password', name)->send_keys('administrator');
$d->find_element('submit', name)->click();

diag("Checking Admin interface");
is($d->get_title, 'Dashboard');
is($d->find_element('//*[@id="masthead"]//h2','xpath')->get_text(), "Dashboard");

diag("Done: admin-login.t");
done_testing;
