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

diag("Go to Customers page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Customers", 'link_text')->click();

diag("Trying to create a empty Customer");
$d->find_element('Create Customer', 'link_text')->click();
$d->scroll_to_element($d->find_element('//table[@id="contactidtable"]/tbody/tr[1]/td//input[@type="checkbox"]'));
$d->unselect_if_selected('//table[@id="contactidtable"]/tbody/tr[1]/td//input[@type="checkbox"]');
$d->scroll_to_element($d->find_element('//table[@id="billing_profileidtable"]/tbody/tr[1]/td//input[@type="checkbox"]'));
$d->unselect_if_selected('//table[@id="billing_profileidtable"]/tbody/tr[1]/td//input[@type="checkbox"]');
$d->find_element('#save', 'css')->click();

diag("Check if error messages appear");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Contact field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid \'billing_profile_id\', not defined.")]'));

diag("Continuing creating a legit customer");
$d->find_element('//*[@id="mod_close"]')->click();

if($pbx == 1){
    $c->create_customer($customerid, $contactmail, $billingname, 'pbx locked');
} else {
    $c->create_customer($customerid, $contactmail, $billingname, 'locked');
}

diag("Search for Customer");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);

diag("Check customer details");
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer ID is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[4]', $contactmail), 'Contact Email is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "locked")]'), 'Status is correct');
$custnum = $d->get_text('//*[@id="Customer_table"]//tr[1]//td[1]');
$compstring = "Customer #" . $custnum . " successfully created - Details";
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), $compstring,  "Correct Alert was shown");

diag("Check if Customer is locked");
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Customer_table_filter"]//input');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Customer is locked',  "Correct Alert was shown");

diag("Go back and edit Customer");
$d->find_element('Back', 'link_text')->click();
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer ID is correct');
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Customer_table_filter"]//input');

diag("Set status to 'active'");
$d->scroll_to_element($d->find_element('//*[@id="status"]'));
$d->find_element('//*[@id="status"]/option[contains(text(), "active")]')->click();
$d->find_element('#save', 'css')->click();

diag("Search for Customer");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);

diag("Check customer details");
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer ID is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[4]', $contactmail), 'Contact Email is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile is correct');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "active")]'), 'Status is correct');
$compstring = "Customer #" . $custnum . " successfully updated";
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), $compstring,  "Correct Alert was shown");

diag("Open Details for our just created Customer");
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Customer_table_filter"]//input');

diag("Edit our contact");
$d->find_element('//div[contains(@class,"accordion-heading")]//a[contains(text(),"Contact Details")]')->click();
$d->find_element('//div[contains(@class,"accordion-body")]//*[contains(@class,"btn-primary") and contains(text(),"Edit Contact")]')->click();
$d->fill_element('div.modal #firstname', 'css', "Alice");
$d->fill_element('#company', 'css', 'Sipwise');
ok($d, 'Inserting name works');
$d->fill_element('#street', 'css', 'Frunze Square');
$d->fill_element('#postcode', 'css', '03141');
$d->fill_element('#city', 'css', 'Kiew');
$d->fill_element('#countryidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#countryidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#countryidtable_filter input', 'css', 'Ukraine'); # Choosing Country
$d->select_if_unselected('//table[@id="countryidtable"]/tbody/tr[1]/td[contains(text(),"Ukraine")]/..//input[@type="checkbox"]');
$d->find_element('#save', 'css')->click(); # Save

diag("Check contact details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contact successfully changed',  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Email")]/../td[2]', $contactmail), "Email is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Name")]/../td[contains(text(), "Alice")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Company")]/../td[contains(text(), "Sipwise")]'), "Company is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Address")]/../td[text()[contains(.,"03141")]]'), "Postal code is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Address")]/../td[text()[contains(.,"Kiew")]]'), "City is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Address")]/../td[text()[contains(.,"Frunze Square")]]'), "Street is correct");

diag("Edit Fraud Limits");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Fraud Limits")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Fraud Limits")]'));
$d->move_and_click('//*[@id="collapse_fraud"]//table//tr//td[text()[contains(.,"Monthly Settings")]]/../td//a[text()[contains(.,"Edit")]]', 'xpath', '//*[@id="customer_details"]//div//a[contains(text(),"Fraud Limits")]');

diag("Fill in invalid info");
$d->fill_element('#fraud_interval_limit', 'css', "invalid");
$d->fill_element('#fraud_interval_notify', 'css', 'stuff');
$d->find_element('#save', 'css')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "stuff is no valid email address")]'));

diag("Fill in valid info");
$d->fill_element('#fraud_interval_limit', 'css', "100");
$d->fill_element('#fraud_interval_notify', 'css', 'mymail@example.org');
$d->find_element('#save', 'css')->click();

diag("Check Fraud Limit details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Fraud settings successfully changed!',  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="collapse_fraud"]//table//tr//td[contains(text(), "Monthly Settings")]/../td[contains(text(), "100")]'), "Limit is correct");
ok($d->wait_for_text('//*[@id="collapse_fraud"]//table//tr//td[contains(text(), "Monthly Settings")]/../td[4]', 'mymail@example.org'), "Mail is correct");

diag("Create a new Phonebook entry");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Phonebook")]'));

diag("Trying to create a empty Phonebook entry");
$d->find_element("Create Phonebook Entry", 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if error messages appear");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Number field is required")]'));

diag("Enter Information");
$d->fill_element('//*[@id="name"]', 'xpath', 'Tester');
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag("Search for Phonebook Entry");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully created',  "Correct Alert was shown");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Phonebook")]'));
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'Tester');

diag("Check Phonebook entry details");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]/tbody/tr[1]/td[contains(text(), "Tester")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]/tbody/tr[1]/td[contains(text(), "0123456789")]'), "Number is correct");

diag("Edit Phonebook entry");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="customer_details"]//div//a[contains(text(), "Phonebook")]');

diag("Change Information");
$d->fill_element('//*[@id="name"]', 'xpath', 'TesterTester');
$d->fill_element('//*[@id="number"]', 'xpath', '987654321');
$d->find_element('//*[@id="save"]')->click();

diag("Check if information has changed");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully updated',  "Correct Alert was shown");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Phonebook")]'));
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'TesterTester');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]/tbody/tr[1]/td[contains(text(), "TesterTester")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]/tbody/tr[1]/td[contains(text(), "987654321")]'), "Number is correct");

diag("Create a new Location");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Locations")]')->click();
$d->find_element("Create Location", 'link_text')->click();

diag("Trying to create a empty Location");
$d->find_element('//*[@id="save"]')->click();

diag("Check if Error messages appear");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Location Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Blocks field is required")]'));

diag('Enter information');
$d->fill_element('//*[@id="name"]', 'xpath', 'Test Location');
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a Test Location');
$d->fill_element('//*[@id="name"]', 'xpath', 'Test Location');
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '127.0.0.1');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="save"]')->click();

diag("Search for Location");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Location successfully created',  "Correct Alert was shown");
$d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Locations")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Locations")]'));
$d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#locations_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'Test Location');

diag("Check location details");
ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "Test Location")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "This is a Test Location")]'), "Description is correct");
ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "127.0.0.1/16")]'), "Network block is correct");

diag("Edit Location");
$d->move_and_click('//*[@id="locations_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="customer_details"]//div//a[contains(text(), "Locations")]');
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a very Test Location');
$d->fill_element('//*[@id="name"]', 'xpath', 'TestTest Location');
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '10.0.0.138');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="save"]')->click();

diag("Search for Location");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Location successfully updated',  "Correct Alert was shown");
$d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Locations")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Locations")]'));
$d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#locations_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'TestTest Location');

diag("Check location details");
ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "TestTest Location")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "This is a very Test Location")]'), "Description is correct");
ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "10.0.0.138/16")]'), "Network block is correct");

diag("Open delete dialog and press cancel");
$c->delete_customer($customerid, 1);
$d->fill_element('//*[@id="Customer_table_filter"]/label/input', 'xpath', $customerid);
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr/td[2]', $customerid), 'Customer is still here');

diag('Open delete dialog and press delete');
$c->delete_customer($customerid, 0);
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Customer successfully terminated',  "Correct Alert was shown");
$d->fill_element('//*[@id="Customer_table_filter"]/label/input', 'xpath', $customerid);
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Customer was deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);
$c->delete_contact($contactmail);
$c->delete_billing_profile($billingname);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_customer.png");
    }
    done_testing;
}