use lib 't/lib';
use Test::More import => [qw(done_testing is diag)];
use Test::WebDriver::Sipwise qw();

diag("Init");
my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
my $d = Test::WebDriver::Sipwise->new (
    'browser_name' => $browsername,
    'proxy' => {'proxyType' => 'system'} );

diag("Loading login page (logout first)");
$d->get_ok("$uri/logout"); # make sure we are logged out
$d->get_ok("$uri/login");
$d->set_implicit_wait_timeout(10000);
$d->default_finder('xpath');

diag("Do Admin Login");
$d->body_text_contains("Admin Sign In");
$d->title_is("");
$d->find_element('username','name')->send_keys('administrator');
$d->find_element('password','name')->send_keys('administrator');
$d->find_element('submit','name')->click();

diag("Checking Admin interface");
$d->title_is('Dashboard');
is($d->find_element('//*[@id="masthead"]//h2','xpath')->get_text(), "Dashboard");

diag("Done: admin-login.t");
done_testing;
