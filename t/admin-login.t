use Sipwise::Base;
use lib 't/lib';
use Test::More import => [qw(done_testing is diag)];
use Test::WebDriver::Sipwise qw();

my $browsername = $ENV{BROWSER_NAME} || ""; #possible values: htmlunit, chrome
my $d = Test::WebDriver::Sipwise->new (browser_name => $browsername,
    'proxy' => {'proxyType' => 'system'});
my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
$d->get_ok("$uri/logout"); #make sure we are logged out
$d->get_ok("$uri/login");
$d->set_implicit_wait_timeout(10000);

diag("Do Admin Login");
$d->find(link_text => 'Admin')->click;
$d->findtext_ok('Admin Sign In');
$d->find(name => 'username')->send_keys('administrator');
$d->find(name => 'password')->send_keys('administrator');
$d->findclick_ok(name => 'submit');

$d->title_is('Dashboard');

done_testing;
