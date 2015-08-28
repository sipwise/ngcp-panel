use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag skip)];
use Selenium::Remote::Driver::Extensions qw();
use TryCatch;

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
is($d->find_element('//*[@id="masthead"]//h2')->get_text(), "Dashboard");

diag("Go to Domains page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('//a[contains(@href,"/domain")]');
$d->find_element('Domains', link_text)->click();

diag("Domains page");
is($d->find_element('//*[@id="masthead"]//h2')->get_text(), "Domains");
SKIP: {
    sleep 1;
    diag("Open Preferences of first Domain");
    my ($row, $edit_link);

    try {
        $row = $d->find_element('//table[@id="Domain_table"]/tbody/tr[1]', xpath);
        $edit_link = $d->find_element('(//table[@id="Domain_table"]/tbody/tr[1]/td//a)[contains(text(),"Preferences")]');
    } catch {
        skip ("It seems, no domains exist", 1);
    }

    ok($edit_link);
    $d->move_to(element => $row);
    $edit_link->click();

    diag('Open the tab "Access Restrictions"');
    #$d->location_ok(qr!domain/\d+/preferences!); #/  # FIXME
    $d->find_element("Access Restrictions", link_text)->click();

    diag("Click edit for the preference concurrent_max");
    sleep 1;
    $row = $d->find_element('//table/tbody/tr/td[normalize-space(text()) = "concurrent_max"]');
    ok($row);
    $edit_link = $d->find_child_element($row, '(./../td//a)[2]');
    ok($edit_link);
    $d->move_to(element => $row);
    $edit_link->click();

    diag("Try to change this to a value which is not a number");
    my $formfield = $d->find_element('concurrent_max', id);
    ok($formfield);
    $formfield->clear();
    $formfield->send_keys('thisisnonumber');
    $d->find_element("save", id)->click();

    diag('Type 789 and click Save');
    $d->find_text('Value must be an integer');
    $formfield = $d->find_element('concurrent_max', id);
    ok($formfield);
    $formfield->clear();
    $formfield->send_keys('789');
    $d->find_element('save', id)->click();
}

done_testing;
# vim: filetype=perl
