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

my $pbx = $ENV{PBX};
my $customerid = ("id" . int(rand(100000)) . "ok");
my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $contactmail = ("contact" . int(rand(100000)) . '@test.org');
my $billingname = ("billing" . int(rand(100000)) . "test");
my $run_ok = 0;
my $custnum;
my $compstring;

if(!$pbx){
    print "---PBX check is DISABLED---\n";
    $pbx = 0;
} else {
    print "---PBX check is ENABLED---\n";
};

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_contact($contactmail, $resellername);
$c->create_billing_profile($billingname, $resellername);

if($pbx == 1){
    $c->create_customer($customerid, $contactmail, $billingname, 'pbx locked');
} else {
    $c->create_customer($customerid, $contactmail, $billingname, 'locked');
}

diag("Try to create an empty Customer");
$d->find_element('Create Customer', 'link_text')->click();
$d->scroll_to_element($d->find_element('//table[@id="contactidtable"]/tbody/tr[1]/td//input[@type="checkbox"]'));
$d->unselect_if_selected('//table[@id="contactidtable"]/tbody/tr[1]/td//input[@type="checkbox"]');
$d->scroll_to_element($d->find_element('//table[@id="billing_profileidtable"]/tbody/tr[1]/td//input[@type="checkbox"]'));
$d->unselect_if_selected('//table[@id="billing_profileidtable"]/tbody/tr[1]/td//input[@type="checkbox"]');
$d->find_element('#save', 'css')->click();

diag("Check if error messages appear");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Contact field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid \'billing_profile_id\', not defined.")]'));
$d->find_element('//*[@id="mod_close"]')->click();

diag("Search Customer");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test was not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);

diag("Check Customer details");
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer ID is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Contact Email is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "locked")]'), 'Status is correct');
$custnum = $d->get_text('//*[@id="Customer_table"]//tr[1]//td[1]');

diag("Check if Customer is locked");
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Customer_table_filter"]//input');
$d->find_element_by_xpath('//div/h2[contains(text(), "Customer Details")]');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Customer is locked',  'Correct Alert was shown');

diag("Go back and edit Customer");
$d->find_element('Back', 'link_text')->click();
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer ID is correct');
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Customer_table_filter"]//input');

diag("Set status to 'active'");
$d->scroll_to_element($d->find_element('//*[@id="status"]'));
$d->find_element('//*[@id="status"]/option[contains(text(), "active")]')->click();
$d->find_element('#save', 'css')->click();

diag("Search Customer");
$compstring = "Customer #" . $custnum . " successfully updated";
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), $compstring,  'Correct Alert was shown');
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);

diag("Check customer details");
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer ID is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Contact Email is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "active")]'), 'Status is correct');
$compstring = "Customer #" . $custnum . " successfully updated";
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), $compstring,  'Correct Alert was shown');

diag("Open Customer details");
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Customer_table_filter"]//input');

diag("Edit Contact");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contact Details")]'));
$d->find_element('//div[contains(@class,"accordion-body")]//*[contains(@class,"btn-primary") and contains(text(),"Edit Contact")]')->click();
$d->fill_element('div.modal #firstname', 'css', "Alice");
$d->fill_element('#company', 'css', 'Sipwise');
ok($d, 'Inserting name works');
$d->fill_element('#street', 'css', 'Frunze Square');
$d->fill_element('#postcode', 'css', '03141');
$d->fill_element('#city', 'css', 'Kiew');
$d->fill_element('#countryidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#countryidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#countryidtable_filter input', 'css', 'Ukraine');
$d->select_if_unselected('//table[@id="countryidtable"]/tbody/tr[1]/td[contains(text(),"Ukraine")]/..//input[@type="checkbox"]');
$d->find_element('#save', 'css')->click();

diag("Check Contact details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contact successfully changed',  'Correct Alert was shown');
if($d->find_element_by_xpath('//*[@id="masthead"]/div/div/div/h2')->get_text() eq "Customers"){ #workaround for misbehaving ngcp panel randomly throwing test out of customer details
    $d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $d->fill_element('#Customer_table_filter input', 'css', $customerid);
    ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Found customer');
    $d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(), "Details")]', 'xpath', '//*[@id="Customer_table_filter"]/label/input');
}
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Contact Details")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Email")]/../td[2][contains(text(), "' . $contactmail . '")]'), 'Email is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Name")]/../td[contains(text(), "Alice")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Company")]/../td[contains(text(), "Sipwise")]'), 'Company is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Address")]/../td[text()[contains(.,"03141")]]'), 'Postal code is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Address")]/../td[text()[contains(.,"Kiew")]]'), 'City is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Address")]/../td[text()[contains(.,"Frunze Square")]]'), 'Street is correct');

diag("Edit Fraud Limits");
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Fraud Limits")]'));
$d->move_and_click('//*[@id="collapse_fraud"]//table//tr//td[text()[contains(.,"Monthly Settings")]]/../td//a[text()[contains(.,"Edit")]]', 'xpath', '//*[@id="customer_details"]//div//a[contains(text(),"Fraud Limits")]');

diag("Fill in invalid values");
$d->fill_element('#fraud_interval_limit', 'css', "invalid");
$d->fill_element('#fraud_interval_notify', 'css', 'stuff');
$d->find_element('#save', 'css')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "stuff is no valid email address")]'));

diag("Fill in valid values");
$d->fill_element('#fraud_interval_limit', 'css', "100");
$d->fill_element('#fraud_interval_notify', 'css', 'mymail@example.org');
$d->find_element('#save', 'css')->click();

diag("Check Fraud Limit details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Fraud settings successfully changed!',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Fraud Limits")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_fraud"]//table//tr//td[contains(text(), "Monthly Settings")]/../td[contains(text(), "100")]'), 'Limit is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_fraud"]//table//tr//td[contains(text(), "Monthly Settings")]/../td[4][contains(text(), "' . 'mymail@example.org' . '")]'), 'Mail is correct');

diag("Go to 'Contract Balance'");
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Contract Balance")]'));

diag("Set Cash Balance without entering anything");
$d->find_element('//*[@id="collapse_balance"]//div//span//a[contains(text(), "Set Cash Balance")]')->click();
$d->fill_element('//*[@id="cash_balance"]', 'xpath', ' ');
$d->fill_element('//*[@id="free_time_balance"]', 'xpath', ' ');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Cash Balance field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Free-Time Balance field is required")]'));

diag("Set invalid Cash Balance");
$d->fill_element('//*[@id="cash_balance"]', 'xpath', 'asdf');
$d->fill_element('//*[@id="free_time_balance"]', 'xpath', 'asdf');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));

diag("Set valid Cash Balance");
$d->fill_element('//*[@id="cash_balance"]', 'xpath', '200');
$d->fill_element('//*[@id="free_time_balance"]', 'xpath', '300');
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Account balance successfully changed!',  'Correct Alert was shown');

diag("Check if Cash Balance was set correctly");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Contract Balance")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//table//tr//td//b[contains(text(), "200.00")]'), 'Cash Balance is correct');
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//table//tr//td//b[contains(text(), "300")]'), 'Free-Time Balance is correct');
ok($d->find_element_by_xpath('//*[@id="balance_intervals_table"]//tr//td[contains(text(), "200.00")]'), 'Cash Balance in Balance intervals table is correct');
ok($d->find_element_by_xpath('//*[@id="balance_intervals_table"]//tr//td[contains(text(), "300")]'), 'Free-Time Balance in Balance intervals table is correct');

diag("Top-up Cash Balance");
$d->find_element('//*[@id="collapse_balance"]//div//span//a[contains(text(), "Top-up Cash")]')->click();

diag("Perform Top-up without entering anything");
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Amount field is required")]'));

diag("Top-up Cash");
$d->fill_element('//*[@id="amount"]', 'xpath', '200');
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Top-up using cash performed successfully!',  'Correct Alert was shown');

diag("Check if Top-up was successful");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Contract Balance")]'));
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//table//tr//td//b[contains(text(), "400.00")]'), "Cash Balance is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_balance"]//table//tr//td//b[contains(text(), "300")]'), "Free-Time Balance is correct");
ok($d->find_element_by_xpath('//*[@id="topup_logs_table"]//tr//td[contains(text(), "200")]'), "Top-Up in Top-Up logs table is correct");

diag("Create a new empty Phonebook entry");
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Phonebook")]'));
$d->find_element('Create Phonebook Entry', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Number field is required")]'));

diag("Enter Information");
$d->fill_element('//*[@id="name"]', 'xpath', 'Tester');
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag("Search Phonebook entry");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully created',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'Tester');

diag("Check Phonebook entry details");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "Tester")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "0123456789")]'), 'Number is correct');

diag("Edit Phonebook entry");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="customer_details"]//div//a[contains(text(), "Phonebook")]');

diag("Change Information");
$d->fill_element('//*[@id="name"]', 'xpath', 'TesterTester');
$d->fill_element('//*[@id="number"]', 'xpath', '987654321');
$d->find_element('//*[@id="save"]')->click();

diag("Check Phonebook entry details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully updated',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Phonebook")]'));
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "TesterTester")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "987654321")]'), 'Number is correct');

diag("Create a new Location");
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Locations")]'));
$d->find_element('Create Location', 'link_text')->click();

diag("Try to create an empty Location");
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Location Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Blocks field is required")]'));

diag("Fill in invalid IP address");
$d->fill_element('//*[@id="name"]', 'xpath', 'Test Location');
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a Test Location');
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', 'invalid');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', 'ip');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Ip is no valid IPv4 or IPv6 address")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid IP address")]'));

diag("Fill in another invalid IP address");
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '10.0.0.256');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Ip is no valid IPv4 or IPv6 address")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid IP address")]'));

diag("Fill in invalid subnet mask");
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '127.0.0.1');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '33');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid mask")]'));

diag("Fill in valid IP address");
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '127.0.0.1');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="save"]')->click();

diag("Search Location");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Location successfully created',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#locations_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'Test Location');

diag("Check Location details");
ok($d->find_element_by_xpath('//*[@id="locations_table"]//tr[1]/td[contains(text(), "Test Location")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="locations_table"]//tr[1]/td[contains(text(), "This is a Test Location")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="locations_table"]//tr[1]/td[contains(text(), "127.0.0.1/16")]'), 'Network block is correct');

diag("Edit Location and add another Location block");
$d->move_and_click('//*[@id="locations_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="customer_details"]//div//a[contains(text(), "Locations")]');
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a very Test Location');
$d->fill_element('//*[@id="name"]', 'xpath', 'TestTest Location');
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '10.0.0.138');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="blocks_add"]')->click();
$d->fill_element('//*[@id="blocks.1.row.ip"]', 'xpath', '127.0.0.1');
$d->fill_element('//*[@id="blocks.1.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Location successfully updated',  'Correct Alert was shown');

diag("Check Location details");
$d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Locations")]')->click();
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Locations")]'));
ok($d->find_element_by_xpath('//*[@id="locations_table"]//tr[1]/td[contains(text(), "TestTest Location")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="locations_table"]//tr[1]/td[contains(text(), "This is a very Test Location")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="locations_table"]//tr[1]/td[contains(text(), "10.0.0.138/16")]'), 'Network block is correct');
ok($d->find_element_by_xpath('//*[@id="locations_table"]//tr[1]/td[contains(text(), "127.0.0.1/16")]'), 'Network block 2 is correct');

diag("Try to NOT delete Customer");
$c->delete_customer($customerid, 1);

diag("Check if Customer is still here");
$d->fill_element('//*[@id="Customer_table_filter"]/label/input', 'xpath', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr/td[2][contains(text(), "' . $customerid . '")]'), 'Customer is still here');

diag("Try to delete Customer");
$c->delete_customer($customerid, 0);
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Customer successfully terminated',  'Correct Alert was shown');

diag("Check if Customer has been deleted");
$d->fill_element('//*[@id="Customer_table_filter"]/label/input', 'xpath', $customerid);
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Customer has been deleted');

$c->delete_contact($contactmail);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);
$c->delete_billing_profile($billingname);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_customer.png");
    }
    $d->quit();
    done_testing;
}