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

diag('Go to Profile Packages page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Profile Packages", 'link_text')->click();

diag('Trying to create a empty Profile Package');
$d->find_element("Create Profile Package", 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag('Check if errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "An initial billing profile mapping with no billing network is required.")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Balance interval definition required.")]'));

diag('Fill in invalid values');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $profilename);
$d->fill_element('//*[@id="description"]', 'xpath', 'nice desc');
$d->fill_element('//*[@id="initial_profiles0rowprofile_idtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#initial_profiles0rowprofile_idtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="initial_profiles0rowprofile_idtable_filter"]/label/input', 'xpath', $billingname);
ok($d->wait_for_text('//*[@id="initial_profiles0rowprofile_idtable"]/tbody/tr[1]/td[2]', $resellername), "Billing Profile found");
$d->select_if_unselected('//*[@id="initial_profiles0rowprofile_idtable"]/tbody/tr[1]/td[4]/input', 'xpath');
$d->fill_element('//*[@id="balance_interval.value"]', 'xpath', 'asdf');
$d->find_element('//*[@id="save"]')->click();

diag('Check if errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be a positive integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Balance interval has to be greater than 0 interval units.")]'));

diag('Fill in antoher invalid value');
$d->fill_element('//*[@id="balance_interval.value"]', 'xpath', '-1');
$d->find_element('//*[@id="save"]')->click();

diag('Check if errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be a positive integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Balance interval has to be greater than 0 interval units.")]'));

diag('Fill in valid value');
$d->fill_element('//*[@id="balance_interval.value"]', 'xpath', '300');
$d->find_element('//*[@id="save"]')->click();

diag('Search for Profile Package');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Profile package successfully created',  "Correct Alert was shown");
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);

diag('Check Details');
ok($d->wait_for_text('//*[@id="packages_table"]/tbody/tr[1]/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="packages_table"]/tbody/tr[1]/td[3]', $profilename), "Name is correct");

diag('Edit Profile Package');
$profilename = ("profile" . int(rand(100000)) . "package");
$d->move_and_click('//*[@id="packages_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="packages_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $profilename);
$d->fill_element('//*[@id="description"]', 'xpath', 'nice desc');
$d->find_element('//*[@id="save"]')->click();

diag('Search for Profile Package');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Profile package successfully updated',  "Correct Alert was shown");
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);

diag('Check Details');
ok($d->wait_for_text('//*[@id="packages_table"]/tbody/tr[1]/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="packages_table"]/tbody/tr[1]/td[3]', $profilename), "Name is correct");

diag('Create a test Customer');
$c->create_customer($customerid, $contactmail, $billingname);

diag('Search for Customer');
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer was found');

diag('Go to Customer details');
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Customer_table_filter"]//input');

diag('Open up "Contract Balance"');
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]')->click();

diag('Enter "Set Cash Balance"');
$d->find_element("Set Cash Balance", "link_text")->click();

diag('Press "Save" without entering anything');
$d->find_element('//*[@id="save"]')->click();

diag('Check Values');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Account balance successfully changed!',  "Correct Alert was shown");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "0.00")]'), "Cash Balance is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "0")]'), "Free-Time Balance is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td[contains(text(), "'. $billingname .'")]'), "Billing Profile is correct");

diag('Enter "Set Cash Balance" again');
$d->find_element("Set Cash Balance", "link_text")->click();
$d->fill_element('//*[@id="cash_balance"]', 'xpath', '300');
$d->fill_element('//*[@id="free_time_balance"]', 'xpath', '50');
$d->find_element('//*[@id="save"]')->click();

diag('Check Values');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Account balance successfully changed!',  "Correct Alert was shown");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "300.00")]'), "Cash Balance is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "50")]'), "Free-Time Balance is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td[contains(text(), "'. $billingname .'")]'), "Billing Profile is correct");

diag('Enter "Top-up Cash"');
$d->find_element("Top-up Cash", "link_text")->click();

diag('Press "Save" without entering anything');
$d->find_element('//*[@id="save"]')->click();

diag('Check error messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Amount field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="amount"]', 'xpath', '200');
$d->fill_element('//*[@id="packageidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packageidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packageidtable_filter"]/label/input', 'xpath', $profilename);
ok($d->wait_for_text('//*[@id="packageidtable"]/tbody/tr[1]/td[3]', $profilename), "Name is correct");
$d->find_element('//*[@id="packageidtable"]/tbody/tr[1]/td[4]/input')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check Details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Top-up using cash performed successfully!',  "Correct Alert was shown");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contract Balance")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "500.00")]'), "Cash Balance is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td//b[contains(text(), "50")]'), "Free-Time Balance is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//div//table//tr//td[contains(text(), "'. $billingname .'")]'), "Billing Profile is correct");

diag("Delete Customer");
$c->delete_customer($customerid);

diag('Go to Profile Packages page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Profile Packages", 'link_text')->click();

diag('Try to NOT delete Profile Package');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);
ok($d->wait_for_text('//*[@id="packages_table"]/tbody/tr[1]/td[3]', $profilename), "Profile Package was found");
$d->move_and_click('//*[@id="packages_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="packages_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Profile Package is still here');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);
ok($d->wait_for_text('//*[@id="packages_table"]/tbody/tr[1]/td[3]', $profilename), "Profile Package was found");

diag('Delete Profile Package');
$d->move_and_click('//*[@id="packages_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="packages_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Profile Package was deleted');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Profile package successfully deleted',  "Correct Alert was shown");
$d->fill_element('//*[@id="packages_table_filter"]/label/input', 'xpath', $profilename);
ok($d->find_element_by_css('#packages_table tr > td.dataTables_empty', 'css'), 'Profile Package was deleted');

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