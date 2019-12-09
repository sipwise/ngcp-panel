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

my $billingname = ("billing" . int(rand(100000)) . "test");
my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $profilename = ("profile" . int(rand(100000)) . "package");
my $contactmail = ("contact" . int(rand(100000)) . '@test.org');
my $customerid = ("id" . int(rand(100000)) . "ok");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_billing_profile($billingname, $resellername);
$c->create_contact($contactmail, $resellername);

diag("Go to 'Profile Packages' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Profile Packages', 'link_text')->click();

diag("Try to create an empty Profile Package");
$d->find_element('Create Profile Package', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Profile Package")]'), 'Edit window has been opened');
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "An initial billing profile mapping with no billing network is required.")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Balance interval definition required.")]'));

diag("Fill in invalid values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $profilename);
$d->fill_element('//*[@id="description"]', 'xpath', 'nice desc');
$d->fill_element('//*[@id="initial_profiles0rowprofile_idtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#initial_profiles0rowprofile_idtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="initial_profiles0rowprofile_idtable_filter"]/label/input', 'xpath', $billingname);
ok($d->find_element_by_xpath('//*[@id="initial_profiles0rowprofile_idtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Billing Profile found');
$d->select_if_unselected('//*[@id="initial_profiles0rowprofile_idtable"]/tbody/tr[1]/td[4]/input', 'xpath');
$d->fill_element('//*[@id="balance_interval.value"]', 'xpath', 'asdf');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be a positive integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Balance interval has to be greater than 0 interval units.")]'));

diag("Fill in antoher invalid value");
$d->fill_element('//*[@id="balance_interval.value"]', 'xpath', '-1');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be a positive integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Balance interval has to be greater than 0 interval units.")]'));

diag("Fill in valid value");
$d->fill_element('//*[@id="balance_interval.value"]', 'xpath', '300');
$d->find_element('//*[@id="save"]')->click();

diag("Search Profile Package");
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="packages_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]', $resellername), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="packages_table"]//tr[1]/td[contains(text(), "' . $profilename . '")]', $profilename), 'Name is correct');

diag("Edit Profile Package");
$profilename = ("profile" . int(rand(100000)) . "package");
$d->move_and_click('//*[@id="packages_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="packages_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Profile Package")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $profilename);
$d->fill_element('//*[@id="description"]', 'xpath', 'nice desc');
$d->find_element('//*[@id="save"]')->click();

diag("Search Profile Package");
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="packages_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]', $resellername), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="packages_table"]//tr[1]/td[contains(text(), "' . $profilename . '")]', $profilename), 'Name is correct');

diag("Create a Customer");
$c->create_customer($customerid, $contactmail, $billingname);

diag("Search Customer");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer was found');

diag("Go to 'Customer details' page");
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Customer_table_filter"]//input');

diag("Go to 'Contract Balance'");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]'));

diag("Try to set Cash Balance without entering anything");
$d->find_element("Set Cash Balance", "link_text")->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Settings")]'), 'Edit window has been opened');
$d->find_element('//*[@id="save"]')->click();

diag("Check values");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "0.00")]'), 'Cash Balance is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "0")]'), 'Free-Time Balance is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td[contains(text(), "'. $billingname .'")]'), 'Billing Profile is correct');

diag("Set Cash Balance with proper values now");
$d->find_element("Set Cash Balance", "link_text")->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Settings")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="cash_balance"]', 'xpath', '300');
$d->fill_element('//*[@id="free_time_balance"]', 'xpath', '50');
$d->find_element('//*[@id="save"]')->click();

diag("Check values");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "300.00")]'), 'Cash Balance is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "50")]'), 'Free-Time Balance is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td[contains(text(), "'. $billingname .'")]'), 'Billing Profile is correct');
ok($d->find_element_by_xpath('//*[@id="balance_intervals_table"]//tr//td[contains(text(), "300.00")]'), 'Cash Balance in Balance intervals table is correct');
ok($d->find_element_by_xpath('//*[@id="balance_intervals_table"]//tr//td[contains(text(), "50")]'), 'Free-Time Balance in Balance intervals table is correct');

diag("Try to Top-up Cash without entering anything");
$d->find_element('Top-up Cash', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Settings")]'), 'Edit window has been opened');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Amount field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="amount"]', 'xpath', '200');
$d->fill_element('//*[@id="packageidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packageidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packageidtable_filter"]/label/input', 'xpath', $profilename);
ok($d->find_element_by_xpath('//*[@id="packageidtable"]//tr[1]/td[contains(text(), "' . $profilename . '")]'), 'Name is correct');
$d->find_element('//*[@id="packageidtable"]/tbody/tr[1]/td[4]/input')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check details");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "500.00")]'), 'Cash Balance is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "50")]'), 'Free-Time Balance is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td[contains(text(), "'. $billingname .'")]'), 'Billing Profile is correct');
ok($d->find_element_by_xpath('//*[@id="topup_logs_table"]//tr//td[contains(text(), "200")]'), 'Top-Up in Top-Up logs table is correct');
ok($d->find_element_by_xpath('//*[@id="topup_logs_table"]//tr//td[contains(text(), "'. $profilename .'")]'), 'Profile Package in Top-Up logs table is correct');

diag("Delete Customer");
$c->delete_customer($customerid);

diag("Go to 'Profile Packages' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Profile Packages', 'link_text')->click();

diag("Try to NOT delete Profile Package");
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);
ok($d->find_element_by_xpath('//*[@id="packages_table"]//tr[1]/td[contains(text(), "' . $profilename . '")]'), 'Profile Package was found');
$d->move_and_click('//*[@id="packages_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="packages_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Profile Package is still here");
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);
ok($d->find_element_by_xpath('//*[@id="packages_table"]//tr[1]/td[contains(text(), "' . $profilename . '")]'), 'Profile Package is still here');

diag("Delete Profile Package");
$d->move_and_click('//*[@id="packages_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="packages_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Profile Package has been deleted");
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Profile Package has been deleted');

$c->delete_contact($contactmail);
$c->delete_billing_profile($billingname);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_profilepackage.png");
    }
    $d->quit();
    done_testing;
}