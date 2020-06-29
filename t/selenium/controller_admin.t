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

my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
my $adminname = ("admin" . int(rand(100000)) . "test");
my $adminpwd = ("pwd" . int(rand(100000)) . "test");
my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag("Go to 'Administrators' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Administrators', 'link_text')->click();

diag("Try to create a new Administrator");
$d->find_element('Create Administrator', 'link_text')->click();

diag("Save without entering anything");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Administrator")]'), 'Edit window has been opened');
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Login field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Please enter a password in this field")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="login"]', 'xpath', $adminname);
$d->fill_element('//*[@id="password"]', 'xpath', $adminpwd);
$d->scroll_to_element($d->find_element('//*[@id="is_superuser"]'));
$d->unselect_if_selected('//*[@id="show_passwords"]');
$d->unselect_if_selected('//*[@id="call_data"]');
$d->unselect_if_selected('//*[@id="billing_data"]');
$d->find_element('//*[@id="save"]')->click();

diag("Search Administrator");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);

diag("Check Administrator details");
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[8][contains(text(), "0")]'), 'Read-Only value is correct');

diag("Edit Administrator details. Enable read-only setting");
$adminname = ("admin" . int(rand(100000)) . "test");
$d->move_and_click('//*[@id="administrator_table"]//tr[1]/td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Administrator")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="login"]', 'xpath', $adminname);
$d->scroll_to_element($d->find_element('//*[@id="is_superuser"]'));
$d->select_if_unselected('//*[@id="read_only"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check Administrator details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[7][contains(text(), "1")]'), 'Read-Only value is correct');

diag("Try to log in new Administrator without any credentials");
$d->get("$uri/logout");
$d->get("$uri/login");
ok($d->find_element('/html/body//div//h1[contains(text(), "Admin Sign In")]'), "Text 'Admin Sign In' found");
is($d->get_title, '', 'No Tab Title was set');
$d->fill_element('#username', 'css', "");
$d->fill_element('#password', 'css', "");
$d->find_element('#submit', 'css')->click();
ok($d->find_element('/html/body//div//h1[contains(text(), "Admin Sign In")]'), "Text 'Admin Sign In' found");
ok($d->find_element('//form//div/span'), "Error Message was shown");

diag("Try to log in new Administrator with invalid credentials");
ok($c->login_ok("invalid", "creds", 1), "Login failed as intended");

diag("Try to log in new Administrator with invalid password");
ok($c->login_ok($adminname, "invalidpass", 1), "Login failed as intended");

diag("Try to log in new Administrator with no password");
$d->get("$uri/logout");
$d->get("$uri/login");
ok($d->find_element('/html/body//div//h1[contains(text(), "Admin Sign In")]'), "Text 'Admin Sign In' found");
is($d->get_title, '', 'No Tab Title was set');
$d->fill_element('#username', 'css', $adminname);
$d->fill_element('#password', 'css', "");
$d->find_element('#submit', 'css')->click();
ok($d->find_element('/html/body//div//h1[contains(text(), "Admin Sign In")]'), "Text 'Admin Sign In' found");
ok($d->find_element('//form//div/span'), "Error Message was shown");

diag("Try to log in new Administrator for real this time");
$c->login_ok($adminname, $adminpwd);

diag("Go to 'Administrators' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Administrators', 'link_text')->click();

diag("Check if only your Administrator is shown");
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), '. $adminname .')]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), '. $resellername .')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[6][contains(text(), "1")]'), 'Read-Only value is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table_info"][contains(text(), "Showing 1 to 1 of 1 entries")]'), 'Only 1 entry exists');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'administrator');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Administrator table is empty');

diag("Go to 'Customers' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Customers', 'link_text')->click();

diag("Check if table is empty");
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Customer table is empty');

diag("Go to 'Domains' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Domains', 'link_text')->click();

diag("Check if table is empty");
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Domain table is empty');

diag("Switch over to default Administrator");
$c->login_ok();

diag("Go to 'Administrators' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Administrators', 'link_text')->click();

diag("Edit Administrator permissions. Make Administrator inactive");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname .'")]'), 'Administrator found');
$d->move_and_click('//*[@id="administrator_table"]//tr[1]/td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Administrator")]'), 'Edit window has been opened');
$d->scroll_to_element($d->find_element('//*[@id="is_superuser"]'));
$d->find_element('//*[@id="is_active"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check Administrator details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[7][contains(text(), "0")]'), 'Active value is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[8][contains(text(), "1")]'), 'Read-Only value is correct');

diag("Do deactivated Administrator login");
$d->get("$uri/logout");
$d->get("$uri/login");
$d->fill_element('#username', 'css', $adminname);
$d->fill_element('#password', 'css', $adminpwd);
$d->find_element('#submit', 'css')->click();
ok($d->find_element_by_xpath('/html/body//div//span[contains(text(), "Invalid username/password")]'), 'Login failed as intended');

diag("Switch over to default Administrator");
$c->login_ok();

diag("Go to 'Administrators' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Administrators', 'link_text')->click();

diag("Give new Administrator default permissions");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Administrator found');
$d->move_and_click('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Administrator")]'), 'Edit window has been opened');
$d->scroll_to_element($d->find_element('//*[@id="is_superuser"]'));
$d->select_if_unselected('//*[@id="is_superuser"]');
$d->select_if_unselected('//*[@id="is_master"]');
$d->select_if_unselected('//*[@id="is_active"]');
$d->unselect_if_selected('//*[@id="read_only"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check Administrator details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[5][contains(text(), "1")]'), 'Master value is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[7][contains(text(), "1")]'), 'Active value is correct');
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[8][contains(text(), "0")]'), 'Read-Only value is correct');

diag("Log in new Administrator");
$c->login_ok($adminname, $adminpwd);

diag("Go to 'Administrators' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Administrators', 'link_text')->click();

diag("Check if Administrator is still here");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Administrator is still here');

diag("Switch over to default Administrator");
$c->login_ok();

diag("Go to 'Administrators' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Administrators', 'link_text')->click();

diag("See if invalid 'lawful_intercept' setting gets rejected");
$d->select_if_unselected('//*[@id="lawful_intercept"]');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Administrator found');
$d->move_and_click('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Administrator")]'), 'Edit window has been opened');
$d->select_if_unselected('//*[@id="lawful_intercept"]');
$d->select_if_unselected('//*[@id="can_reset_password"]');
$d->find_element('//*[@id="save"]')->click();
ok($d->find_element_by_xpath('//form//div[@class="control-group error"]//span[@class="help-inline"]'), 'Error message was shown');
$d->unselect_if_selected('//*[@id="lawful_intercept"]');
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully updated',  'Correct Alert was shown');

diag("Try to NOT delete Administrator");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Administrator found');
$d->move_and_click('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Administrator is still here");
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_xpath('//*[@id="administrator_table"]//tr[1]/td[contains(text(), "' . $adminname . '")]'), 'Administrator is still here');

diag("Try to delete Administrator");
$d->move_and_click('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="administrator_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Administrator has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Administrator successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Administrator has been deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successful");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_admin.png");
    }
    $d->quit();
    done_testing;
}
