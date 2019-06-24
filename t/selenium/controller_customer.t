use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;
use TryCatch;

sub ctr_customer {
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
    try {
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
            $c->create_customer($customerid, $contactmail, $billingname, 1);
        } else {
            $c->create_customer($customerid, $contactmail, $billingname);
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

        diag("Edit Customer");
        $d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Customer_table_filter"]//input');

        diag("Set status to 'locked'");
        $d->scroll_to_element($d->find_element('//*[@id="status"]'));
        $d->find_element('//*[@id="status"]/option[contains(text(), "locked")]')->click();
        $d->find_element('#save', 'css')->click();

        diag("Check if status has changed for customer");
        ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "locked")]'), 'Status has changed');

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
        $d->fill_element('#fraud_interval_limit', 'css', "100");
        $d->fill_element('#fraud_interval_notify', 'css', 'mymail@example.org');
        $d->find_element('#save', 'css')->click();

        diag("Check Fraud Limit details");
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
        $d->fill_element('//*[@id="Customer_table_filter"]/label/input', 'xpath', $customerid);
        ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Customer was deleted');

        $c->delete_reseller_contract($contractid);
        $c->delete_reseller($resellername);
        $c->delete_contact($contactmail);
        $c->delete_billing_profile($billingname);
    } catch {
        is("tests", "failed", "This test wasnt successful, check complete test logs for more info");
        diag("-----------------------SCRIPT HAS CRASHED-----------------------");
        if($d->find_text("Sorry!")) {
            my $crashvar = $d->find_element_by_css('.error-container > h2:nth-child(2)')->get_text();
            my $incident = $d->find_element_by_css('.error-details > div:nth-child(2)')->get_text();
            my $time = $d->find_element_by_css('.error-details > div:nth-child(3)')->get_text();
            my $realtime = localtime();
            diag("Server error: $crashvar");
            diag($incident);
            diag($time);
            diag("Perl localtime(): $realtime");
        } else {
            diag("Could not detect Server issues. Maybe script problems?");
            diag("If you still want to check server logs, here's a timestamp");
            my $realtime = localtime();
            diag("Perl localtime(): $realtime");
        }
        diag("----------------------------------------------------------------");
    }

}

if(! caller) {
    ctr_customer();
    done_testing;
}

1;