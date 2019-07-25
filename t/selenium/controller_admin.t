use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

my ($port) = @_;
my $d = Selenium::Collection::Functions::create_driver($port);
my $c = Selenium::Collection::Common->new(
    driver => $d
);

my $adminname = ("admin" . int(rand(100000)) . "test");
my $adminpwd = ("pwd" . int(rand(100000)) . "test");
my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag('Go to admin interface');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Administrators", 'link_text')->click();

diag('Trying to create a new administrator');
$d->find_element("Create Administrator", 'link_text')->click();

diag('Trying to save without entering anything');
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->find_element('//*[@id="save"]')->click();

diag('Check if errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Login field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Please enter a password in this field")]'));

diag('Fill in values');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="login"]', 'xpath', $adminname);
$d->fill_element('//*[@id="password"]', 'xpath', $adminpwd);
$d->find_element('//*[@id="save"]')->click();

diag('Search for our new admin');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully created',  "Correct Alert was shown");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);

diag('Check Admin details');
ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[3]', $adminname), "Name is correct");
ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[2]', $resellername), "Reseller is correct");
ok($d->find_element_by_xpath('//*[@id="administrator_table"]/tbody/tr[1]/td[6][contains(text(), "0")]'), "Read-Only value is correct");

diag('Edit Admin details');
$adminname = ("admin" . int(rand(100000)) . "test");
$d->move_and_click('//*[@id="administrator_table"]//tr[1]/td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
$d->fill_element('//*[@id="login"]', 'xpath', $adminname);
$d->scroll_to_element($d->find_element('//form//div/label[contains(text(), "Read only")]'));
$d->select_if_unselected('//*[@id="read_only"]');
$d->find_element('//*[@id="save"]')->click();

diag('Check Admin details');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully updated',  "Correct Alert was shown");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[3]', $adminname), "Name is correct");
ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[6]', '1'), "Read-Only value is correct");

diag('New admin tries to login now');
$c->login_ok($adminname, $adminpwd);

diag('Go to admin interface');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Administrators", 'link_text')->click();

diag('Check if only your admin is shown');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]/tbody/tr[1]/td[contains(text(), '. $adminname .')]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="administrator_table"]/tbody/tr[1]/td[contains(text(), '. $resellername .')]'), "Reseller is correct");
ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[5]', '1'), "Read-Only value is correct");
ok($d->wait_for_text('//*[@id="administrator_table_info"]', 'Showing 1 to 1 of 1 entries'), "Only 1 entry exists");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'administrator');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Admin table is empty');

diag("Go to Customers page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Customers", 'link_text')->click();

diag("Check if table is empty");
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Customer Table is empty');

diag('Go to domains page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Domains", 'link_text')->click();

diag("Check if table is empty");
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Domain Table is empty');

diag('Switch over to default admin');
$c->login_ok();

diag('Go to admin interface');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Administrators", 'link_text')->click();

diag('Try to NOT delete Administrator');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[3]', $adminname), "Admin found");
$d->move_and_click('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if admin is still here');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[3]', $adminname), "Admin is still here");

diag('Try to delete Administrator');
$d->move_and_click('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if admin is deleted');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully deleted',  "Correct Alert was shown");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Admin was deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_admin.png");
    }
    $d->quit();
    done_testing;
}