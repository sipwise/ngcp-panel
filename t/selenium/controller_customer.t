use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

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
        $c->create_customer($customerid, $contactmail, $billingname, 1);
    } else {
        $c->create_customer($customerid, $contactmail, $billingname);
    }

    diag("Search for Customer");
    $d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
    $d->fill_element('#Customer_table_filter input', 'css', $customerid);
    ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $customerid), 'Customer found');

    diag("Check customer details");
    ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer ID is correct');
    ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
    ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[4]', $contactmail), 'Contact Email is correct');
    ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile is correct');

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
    $d->find_element("Create Phonebook Entry", 'link_text')->click();
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

    diag("Create a new Location");
    $d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Locations")]')->click();
    $d->find_element("Create Location", 'link_text')->click();

    diag('Enter necessary information');
    $d->fill_element('//*[@id="name"]', 'xpath', 'Test Location');
    $d->fill_element('//*[@id="description"]', 'xpath', 'This is a Test Location');
    $d->fill_element('//*[@id="name"]', 'xpath', 'Test Location');
    $d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '127.0.0.1');
    $d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '16');
    $d->find_element('//*[@id="save"]')->click();

    diag("Search for Location");
    $d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Locations")]')->click();
    $d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#locations_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'Test Location');

    diag("Check location details");
    ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "Test Location")]'), "Name is correct");
    ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "This is a Test Location")]'), "Description is correct");
    ok($d->find_element_by_xpath('//*[@id="locations_table"]/tbody/tr[1]/td[contains(text(), "127.0.0.1/16")]'), "Network block is correct");

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

}

if(! caller) {
    ctr_customer();
    done_testing;
}

1;