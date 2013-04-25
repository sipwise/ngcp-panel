use Sipwise::Base;
use lib 't/lib';
use Test::More import => [qw(done_testing is ok)];
use Test::WebDriver::Sipwise qw();

my $browsername = $ENV{BROWSER_NAME} || ""; #possible values: htmlunit, chrome
my $d = Test::WebDriver::Sipwise->new (browser_name => $browsername,
    'proxy' => {'proxyType' => 'system'});
$d->set_window_size(800,1280) if ($browsername ne "htmlunit");
my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
$d->get_ok("$uri/logout"); #make sure we are logged out
$d->get_ok("$uri/login");
$d->set_implicit_wait_timeout(1000);

$d->findtext_ok('Subscriber Sign In');

$d->findclick_ok(link_text => 'Admin');
$d->find(name => 'username')->send_keys('administrator');
$d->find(name => 'password')->send_keys('administrator');
$d->findclick_ok(name => 'submit');

$d->title_is('Dashboard');

$d->findclick_ok(xpath => '//*[@id="main-nav"]//*[contains(text(),"Settings")]');
$d->find_ok(xpath => '//a[contains(@href,"/domain")]');
$d->findclick_ok(link_text => "Domains");

$d->title_is("Domains");
$d->findclick_ok(xpath => "/html/body/div/div[4]/div/div[3]/table/tbody/tr/td/a");

$d->location_like(qr!domain/\d+/preferences!); #/
$d->findclick_ok(link_text => "Access Restrictions");

my $row = $d->find(xpath => '//table/tbody/tr/td[normalize-space(text()) = "concurrent_max"]');
ok($row);
my $edit_link = $d->find_child_element($row, '(./../td//a)[2]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;

my $formfield = $d->find('id' => 'concurrent_max');
ok($formfield);
$formfield->clear;
$formfield->send_keys('thisisnonumber');
$d->findclick_ok(id => 'save');

$d->findtext_ok('Value must be an integer');
$formfield = $d->find('id' => 'concurrent_max');
ok($formfield);
$formfield->clear;
$formfield->send_keys('789');
$d->findclick_ok(id => 'save');

done_testing;
# vim: filetype=perl
