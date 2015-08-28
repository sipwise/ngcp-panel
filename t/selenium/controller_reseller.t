use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag)];
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
is($d->find_element('//*[@id="masthead"]//h2')->get_text(), "Dashboard");

diag("Go to reseller list");
$d->find_element('//a[@class="btn" and contains(@href,"/reseller")]')->click();

diag("Search nonexisting reseller");
my $searchfield = $d->find_element('#Resellers_table_filter label input', css);
ok($searchfield);
$searchfield->send_keys('donotfindme');

diag("Verify that nothing is shown");
my $elem = $d->find_element('#Resellers_table td.dataTables_empty', css);
ok($elem);
is($elem->get_text,'No matching records found');

diag('Search for "1" in resellers');
$searchfield->clear();
$searchfield->send_keys('active');
$d->find_element('#Resellers_table tr.sw_action_row', css);
is($d->find_element('//table[@id="Resellers_table"]//tr[1]/td[1]')->get_text(), '1');

diag("Going to create a reseller");
$d->find_element('Create Reseller', link_text)->click();
$d->find_element('save', id)->click();
$d->find_text("Contract field is required");
$d->find_text("Name field is required");
$d->find_element('mod_close', id)->click();

diag("Click Edit on the first reseller shown (first row)");
sleep 1; #prevent a StaleElementReferenceException
my $row = $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]');
ok($row);
$d->move_to(element => $row);
my $btn = $d->find_child_element($row, './/a[contains(text(),"Edit")]');
ok($btn);
$btn->click();
#is($d->find_element("name", id)->get_attribute("value"), "reseller 1");
$d->find_element('mod_close', id)->click();

diag("Click Terminate on the first reseller shown");
sleep 1; #prevent a StaleElementReferenceException
$row = $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]');
ok($row);
$d->move_to(element => $row);
$btn = $d->find_child_element($row, './/a[contains(@class,"btn-secondary")]');
ok($btn);
$btn->click();
$d->find_text("Are you sure?");
$d->find_element('//div[@id="dataConfirmModal"]//button[contains(text(),"Cancel")]')->click();

done_testing;
# vim: filetype=perl
