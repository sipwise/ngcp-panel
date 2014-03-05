use Sipwise::Base;
use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag skip)];
use Test::WebDriver::Sipwise qw();

my $browsername = $ENV{BROWSER_NAME} || ""; #possible values: htmlunit, chrome
my $d = Test::WebDriver::Sipwise->new (browser_name => $browsername,
    'proxy' => {'proxyType' => 'system'});
$d->set_window_size(1024,1280) if ($browsername ne "htmlunit");
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

$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Dashboard")]');

diag("Go to Domains page");
$d->findclick_ok(xpath => '//*[@id="main-nav"]//*[contains(text(),"Settings")]');
$d->find_ok(xpath => '//a[contains(@href,"/domain")]');
$d->findclick_ok(link_text => "Domains");

$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Domains")]');
SKIP: {
    sleep 1;
    diag("Open Preferences of first Domain");
    my ($row, $edit_link);
    try {
        $row = $d->find(xpath => '//table[@id="Domain_table"]/tbody/tr[1]');
        $edit_link = $d->find(xpath => '(//table[@id="Domain_table"]/tbody/tr[1]/td//a)[contains(text(),"Preferences")]');
    } catch {
        skip ("It seems, no domains exist", 1);
    }

    ok($edit_link);
    $d->move_to(element => $row);
    $edit_link->click;

    diag('Open the tab "Access Restrictions"');
    $d->location_like(qr!domain/\d+/preferences!); #/
    $d->findclick_ok(link_text => "Access Restrictions");

    diag("Click edit for the preference concurrent_max");
    sleep 1;
    $row = $d->find(xpath => '//table/tbody/tr/td[normalize-space(text()) = "concurrent_max"]');
    ok($row);
    $edit_link = $d->find_child_element($row, '(./../td//a)[2]');
    ok($edit_link);
    $d->move_to(element => $row);
    $edit_link->click;

    diag("Try to change this to a value which is not a number");
    my $formfield = $d->find('id' => 'concurrent_max');
    ok($formfield);
    $formfield->clear;
    $formfield->send_keys('thisisnonumber');
    $d->findclick_ok(id => 'save');

    diag('Type 789 and click Save');
    $d->findtext_ok('Value must be an integer');
    $formfield = $d->find('id' => 'concurrent_max');
    ok($formfield);
    $formfield->clear;
    $formfield->send_keys('789');
    $d->findclick_ok(id => 'save');
}

done_testing;
# vim: filetype=perl
