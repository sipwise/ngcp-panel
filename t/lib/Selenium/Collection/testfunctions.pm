use warnings;
use strict;
use Moo;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
Test::More->builder->no_ending(1);
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;

sub ctr_admin {
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
        },
        port => '4444'
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $adminname = ("admin" . int(rand(100000)) . "test");
    my $adminpwd = ("pwd" . int(rand(100000)) . "test");
    my $resellername = ("reseller" . int(rand(100000)) . "test");
    my $contractid = ("contract" . int(rand(100000)) . "test");

    $c->login_ok();
    $c->create_reseller_contract($contractid);
    $c->create_reseller($resellername, $contractid);

    diag('Go to admin interface');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Administrators", 'link_text')->click();

    diag('Trying to create a new administrator');
    $d->find_element("Create Administrator", 'link_text')->click();

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
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
    ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[3]', $adminname), "Admin found");

    diag('New admin tries to login now');
    $c->login_ok($adminname, $adminpwd);

    diag('Go to admin interface');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Administrators", 'link_text')->click();

    diag('Switch over to default admin');
    $c->login_ok();

    diag('Go to admin interface');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Administrators", 'link_text')->click();

    diag('Try to delete Administrator');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
    ok($d->wait_for_text('//*[@id="administrator_table"]/tbody/tr[1]/td[3]', $adminname), "Admin found");
    $d->move_action(element => $d->find_element('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Delete")]'));
    $d->find_element('//*[@id="administrator_table"]/tbody/tr[1]/td//a[contains(text(), "Delete")]')->click();
    $d->find_element('//*[@id="dataConfirmOK"]')->click();

    diag('Check if admin is deleted');
    $d->fill_element('//*[@id="administrator_table_filter"]/label/input', 'xpath', $adminname);
    ok($d->find_element_by_css('#administrator_table tr > td.dataTables_empty', 'css'), 'Admin was deleted');

    $c->delete_reseller_contract($contractid);
    $c->delete_reseller($resellername);

    return 1;
}

sub ctr_billing {
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
        browser_name => $browsername,
        extra_capabilities => {
            acceptInsecureCerts => \1,
        },
        port => '5555'
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $billingname = ("billing" . int(rand(100000)) . "test");

    $c->login_ok();

    diag("Go to Billing page");
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element('//a[contains(@href,"/domain")]');
    $d->find_element("Billing", 'link_text')->click();

    diag("Create a billing profile");
    $d->find_element('//*[@id="masthead"]//h2[contains(text(),"Billing Profiles")]')->click();
    $d->find_element('Create Billing Profile', 'link_text')->click();
    $d->find_element('//div[contains(@class,modal-body)]//table[@id="reselleridtable"]/tbody/tr[1]/td//input[@type="checkbox"]')->click();
    $d->fill_element('#name', 'css', $billingname);
    $d->fill_element('[name=handle]', 'css', $billingname);
    $d->find_element('//select[@id="fraud_interval_lock"]/option[contains(text(),"foreign calls")]')->click();
    $d->find_element('//div[contains(@class,"modal")]//input[@type="submit"]')->click();

    diag('Search for Test Profile in billing profile');
    $d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);
    ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');

    diag('Check if other values are correct');
    ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[3]', 'default'), 'Correct reseller was found');

    diag("Open edit dialog for Test Profile");
    $d->move_action(element => $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Edit")]'));
    $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Edit")]')->click();

    diag("Edit Test Profile");
    my $elem = $d->find_element('#name', 'css');
    ok($elem);
    $d->fill_element('#interval_charge', 'css', '3.2');
    $d->find_element('#save', 'css')->click();
    sleep 1;

    diag('Open "Fees" for Test Profile');
    $d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);
    ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
    $d->move_action(element => $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Fees")]'));
    $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Fees")]')->click();

    diag("Create a billing fee");
    $d->find_element('Create Fee Entry', 'link_text')->click();
    $d->find_element('//div[contains(@class,"modal")]//input[@value="Create Zone"]')->click();
    diag("Create a billing zone (redirect from previous form)");
    $d->fill_element('#zone', 'css', 'testingzone');
    $d->fill_element('#detail', 'css', 'testingdetail');
    $d->find_element('#save', 'css')->click();
    diag("Back to orignial form (create billing fees)");
    $d->select_if_unselected('//div[contains(@class,"modal")]//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..//input[@type="checkbox"]');
    $d->fill_element('#source', 'css', '.*');
    $d->fill_element('#destination', 'css', '.+');
    $d->find_element('//*[@id="direction"]/option[@value="in"]')->click();
    $d->find_element('#save', 'css')->click();

    diag("Check if billing fee values are correct");
    $d->fill_element('//*[@id="billing_fee_table_filter"]//input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $d->fill_element('//*[@id="billing_fee_table_filter"]//input', 'xpath', '.+');
    ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[2]', '.*'), 'Source pattern is correct');
    ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[3]', '.+'), 'Destination pattern is correct');
    ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[5]', 'in'), 'Direction pattern is correct');
    ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[6]', 'testingdetail'), 'Billing zone is correct');

    diag("Delete billing fee");
    $d->move_action(element => $d->find_element('//*[@id="billing_fee_table"]/tbody/tr[1]/td//div//a[contains(text(), "Delete")]'));
    $d->find_element('//*[@id="billing_fee_table"]/tbody/tr[1]/td//div//a[contains(text(), "Delete")]')->click();
    ok($d->find_text("Are you sure?"), 'Delete dialog appears');
    $d->find_element('#dataConfirmOK', 'css')->click();
    ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

    diag("Check if billing fee was deleted");
    $d->find_element('//*[@id="billing_fee_table_filter"]//input')->clear();
    $d->fill_element('//*[@id="billing_fee_table_filter"]//input', 'xpath', '.+');
    ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Billing fee was deleted');

    diag("Click Edit Zones");
    $d->find_element("Edit Zones", 'link_text')->click();
    ok($d->find_element('//*[@id="masthead"]//h2[contains(text(),"Billing Zones")]'));

    diag("Check if billing zone values are correct");
    ok($d->wait_for_text('//*[@id="billing_zone_table"]/tbody/tr/td[2]', 'testingzone'), 'Billing zone name is correct');
    ok($d->wait_for_text('//*[@id="billing_zone_table"]/tbody/tr/td[3]', 'testingdetail'), 'Billing zone detail is correct');

    diag("Delete testingzone");
    $d->fill_element('//*[@id="billing_zone_table_filter"]//input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $d->fill_element('//*[@id="billing_zone_table_filter"]//input', 'xpath', 'testingdetail');
    my $row = $d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..');
    ok($row);
    $d->move_action(element => $row);
    $d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..//a[contains(text(),"Delete")]')->click();
    ok($d->find_text("Are you sure?"), 'Delete dialog appears');
    $d->find_element('#dataConfirmOK', 'css')->click();

    diag("Check if Billing zone was deleted");
    $d->find_element('//*[@id="billing_zone_table_filter"]//input')->clear();
    $d->fill_element('//*[@id="billing_zone_table_filter"]//input', 'xpath', 'testingdetail');
    ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty'), 'Billing zone was deleted');

    diag("Go to Billing page (again)");
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    ok($d->find_element('//a[contains(@href,"/domain")]'));
    $d->find_element("Billing", 'link_text')->click();

    diag('Open "Edit Peak Times" for Test Profile');
    $d->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
    ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
    $d->move_action(element => $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Off-Peaktimes")]'));
    $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Off-Peaktimes")]')->click();

    diag("Edit Wednesday");
    $d->move_and_click('//table//td[contains(text(),"Wednesday")]/..//a[text()[contains(.,"Edit")]]', 'xpath', '//h3[contains(text(),"Weekdays")]');
    ok($d->find_text("Edit Wednesday"), 'Edit dialog was opened');

    diag("add/delete a time def to Wednesday");
    $d->fill_element('#start', 'css', "04:20:00");
    $d->fill_element('#end', 'css', "13:37:00");
    $d->find_element('#add', 'css')->click();
    $d->find_element('#mod_close', 'css')->click();

    diag("check if time def has correct values");
    ok($d->find_element_by_xpath('//*[@id="content"]/div/table/tbody/tr[3]/td[text()[contains(.,"04:20:00")]]'), "Time def 1 is correct");
    ok($d->find_element_by_xpath('//*[@id="content"]/div/table/tbody/tr[3]/td[text()[contains(.,"13:37:00")]]'), "Time def 2 is correct");

    diag("Create a Date Definition");
    $d->find_element('Create Special Off-Peak Date', 'link_text')->click();
    $d->fill_element('#start', 'css', "2008-02-28 04:20:00");
    $d->fill_element('#end', 'css', "2008-02-28 13:37:00");
    $d->find_element('#save', 'css')->click();

    diag("Check if created date definition is correct");
    $d->scroll_to_element($d->find_element('//div[contains(@class, "dataTables_filter")]//input'));
    $d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#date_definition_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', '2008-02-28 04:20:00');
    ok($d->wait_for_text('//*[@id="date_definition_table"]/tbody/tr/td[2]', '2008-02-28 04:20:00'), 'Start Date definition is correct');
    ok($d->wait_for_text('//*[@id="date_definition_table"]/tbody/tr/td[3]', '2008-02-28 13:37:00'), 'End Date definition is correct');

    diag("Delete my created date definition");
    $d->move_action(element => ($d->find_element('//*[@id="date_definition_table"]/tbody//tr//td//div//a[contains(text(),"Delete")]')));
    $d->find_element('//*[@id="date_definition_table"]/tbody//tr//td//div//a[contains(text(),"Delete")]')->click();
    ok($d->find_text("Are you sure?"), 'Delete dialog appears');
    $d->find_element('#dataConfirmOK', 'css')->click();

    diag("Terminate our Billing Profile");
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Billing", 'link_text')->click();
    $d->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
    ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
    $d->move_action(element => $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Terminate")]'));
    $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Terminate")]')->click();
    ok($d->find_text("Are you sure?"), 'Delete dialog appears');
    $d->find_element('#dataConfirmOK', 'css')->click();

    diag("Check if Billing Profile has been removed");
    $d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
    ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Billing Profile has been removed');

    return 1;
}

sub ctr_customer() {
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
        browser_name => $browsername,
        extra_capabilities => {
            acceptInsecureCerts => \1,
        },
        port => '6666'
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $pbx = $ENV{PBX};

    if(!$pbx){
        print "---PBX check is DISABLED---\n";
        $pbx = 0;
    } else {
        print "---PBX check is ENABLED---\n";
    };

    my $customerid = ("id" . int(rand(100000)) . "ok");

    $c->login_ok();

    if($pbx == 1){
        $c->create_customer($customerid, 1);
    } else {
        $c->create_customer($customerid);
    }

    diag("Search for Customer");
    $d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
    $d->fill_element('#Customer_table_filter input', 'css', $customerid);
    ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $customerid), 'Customer found');

    diag("Check customer details");
    ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer ID is correct');
    ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "default")]'), 'Reseller is correct');
    ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "default-customer")]', 'default-customer@default.invalid'), 'Contact Email is correct');
    ok($d->find_element_by_xpath('//*[@id="Customer_table"]/tbody/tr[1]/td[contains(text(), "Default Billing Profile")]'), 'Billing Profile is correct');

    diag("Open Details for our just created Customer");
    $d->move_action(element=> $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]'));
    $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]')->click();

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
    ok($d, 'Successfuly added a Country');
    $d->find_element('#save', 'css')->click(); # Save

    diag("Check contact details");
    ok($d->wait_for_text('//*[@id="collapse_contact"]//table//tr//td[contains(text(), "Email")]/../td[2]', 'default-customer@default.invalid'), "Email is correct");
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

    return 1;
}

sub ctr_domain {
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
        },
        port => '7777'
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $domainstring = ("domain" . int(rand(100000)) . ".example.org");

    $c->login_ok();
    $c->create_domain($domainstring);

    diag("Check if entry exists and if the search works");
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);

    diag("Check domain details");
    ok($d->find_element_by_xpath('//*[@id="Domain_table"]/tbody/tr[1]/td[contains(text(), "default")]'), "Reseller is correct");
    ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[contains(text(), "domain")]', $domainstring), "Domain name is correct");

    diag("Open Preferences of first Domain");
    $d->move_and_click('//*[@id="Domain_table"]//tr[1]//td//a[contains(text(), "Preferences")]', 'xpath');

    diag('Open the tab "Access Restrictions"');
    $d->find_element("Access Restrictions", 'link_text')->click();

    diag("Click edit for the preference concurrent_max");
    $d->move_and_click('//table//tr/td[contains(text(), "concurrent_max")]/../td//a[contains(text(), "Edit")]', 'xpath');

    diag("Try to change this to a value which is not a number");
    $d->fill_element('#concurrent_max', 'css', 'thisisnonumber');
    $d->find_element("#save", 'css')->click();

    diag('Type 789 and click Save');
    ok($d->find_text('Value must be an integer'), 'Wrong value detected');
    $d->fill_element('#concurrent_max', 'css', '789');
    $d->find_element('#save', 'css')->click();

    diag('Check if value has been applied');
    ok($d->find_element_by_xpath('//table/tbody/tr/td[contains(text(), "concurrent_max")]/../td[contains(text(), "789")]'), "Value has been applied");

    diag("Click edit for the preference allowed_ips");
    $d->move_action(element=> $d->find_element('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td/div/a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td/div/a[contains(text(), "Edit")]')->click();

    diag("Enter an IP address");
    $d->fill_element('//*[@id="allowed_ips"]', 'xpath', '127.0.0.0.0');
    $d->find_element('//*[@id="add"]')->click();
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//div//span[contains(text(), "Invalid IPv4 or IPv6 address")]'), "Invalid IP address detected");
    $d->fill_element('//*[@id="allowed_ips"]', 'xpath', '127.0.0.1');
    $d->find_element('//*[@id="add"]')->click();
    $d->find_element('//*[@id="mod_close"]')->click();

    diag("Check if IP address has been added");
    ok($d->find_element_by_xpath('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td[contains(text(), "127.0.0.1")]'), "IP address has beeen found");

    diag("Open delete dialog and press cancel");
    $c->delete_domain($domainstring, 1);
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
    ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[3]', $domainstring), 'Domain is still here');

    diag('Open delete dialog and press delete');
    $c->delete_domain($domainstring, 0);
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
    ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Domain was deleted');

    return 1;
}

sub ctr_peering {
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
        browser_name => $browsername,
        extra_capabilities => {
            acceptInsecureCerts => \1,
        },
        port => '4444'
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $groupname = ("group" . int(rand(100000)) . "test");
    my $servername = ("peering" . int(rand(100000)) . "server");

    $c->login_ok();

    diag("Go to Peerings page");
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Peerings", 'link_text')->click();

    diag("Create a Peering Group");
    $d->find_element('//*[@id="masthead"]//h2[contains(text(),"SIP Peering Groups")]');
    my $peerings_uri = $d->get_current_url();
    $d->find_element('Create Peering Group', 'link_text')->click();

    diag("Create a Peering Contract");
    $d->find_element('//input[@type="button" and @value="Create Contract"]')->click();
    $d->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#contactidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'default-system@default.invalid');
    ok($d->wait_for_text('//*[@id="contactidtable"]/tbody/tr[1]/td[4]', 'default-system@default.invalid'), "Default Contact was found");
    $d->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]//input[@type="checkbox"]');
    $d->scroll_to_element($d->find_element('//table[@id="billing_profileidtable"]'));
    $d->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]//input[@type="checkbox"]');
    $d->find_element('//div[contains(@class,"modal-body")]//div//select[@id="status"]/option[@value="active"]')->click();
    $d->find_element('//div[contains(@class,"modal")]//input[@type="submit"]')->click();
    ok($d->find_text('Create Peering Group'), 'Succesfully went back to previous form'); # Should go back to prev form

    diag("Continue creating a Peering Group");
    $d->fill_element('#name', 'css', $groupname);
    $d->fill_element('#description', 'css', 'A group created for testing purposes');
    $d->select_if_unselected('//table[@id="contractidtable"]/tbody/tr[1]//input[@type="checkbox"]');
    $d->find_element('#save', 'css')->click();

    diag("Search for the newly created Peering Group");
    $d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);

    diag("Check Peering Group Details");
    ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[2]', 'default-system@default.invalid'), 'Contact is correct');
    ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Name is correct');
    ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[5]', 'A group created for testing purposes'), 'Description is correct');

    diag("Edit Peering Group");
    $d->move_and_click('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Details")]', 'xpath');

    diag("Create Outbound Peering Rule");
    $d->find_element('//a[contains(text(),"Create Outbound Peering Rule")]')->click();
    $d->fill_element('#callee_prefix', 'css', '43');
    $d->fill_element('#callee_pattern', 'css', '^sip');
    $d->fill_element('#caller_pattern', 'css', '999');
    $d->fill_element('#description', 'css', 'for testing purposes');
    $d->find_element('#save', 'css')->click();

    diag("Check Outbound Peering Rule Details");
    ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "43")]'), "Prefix is correct");
    ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "^sip")]'), "Callee Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "999")]'), "Caller Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "for testing purposes")]'), "Description is correct");

    diag("Create Inbound Peering Rule");
    $d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]')->click();
    $d->fill_element('//*[@id="pattern"]', 'xpath', '^sip');
    $d->fill_element('//*[@id="reject_code"]', 'xpath', '403');
    $d->fill_element('//*[@id="reject_reason"]', 'xpath', 'forbidden');
    $d->find_element('#save', 'css')->click();

    diag("Check Inbound Peering Rule Details");
    ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "^sip")]'), "Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "403")]'), "Reject Code is correct");
    ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "forbidden")]'), "Reject Reason is correct");

    diag("Create a Peering Server");
    $d->find_element('//a[contains(text(),"Create Peering Server")]')->click();
    $d->fill_element('#name', 'css', $servername);
    $d->fill_element('#ip', 'css', '10.0.0.100');
    $d->fill_element('#host', 'css', 'sipwise.com');
    $d->find_element('#save', 'css')->click();
    ok($d->find_text('Peering server successfully created'), 'Text "Peering server successfully created" appears');
    my $server_rules_uri = $d->get_current_url();

    diag("Check Peering Server Details");
    ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr/td[2]', $servername), "Name is correct");
    ok($d->find_element_by_xpath('//*[@id="peering_servers_table"]/tbody/tr/td[contains(text(), "10.0.0.100")]'), "IP is correct");
    ok($d->find_element_by_xpath('//*[@id="peering_servers_table"]/tbody/tr/td[contains(text(), "sipwise.com")]'), "Host is correct");

    diag('Go into Peering Server Preferences');
    $d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
    $d->find_element('#peering_servers_table tr > td.dataTables_empty', 'css');
    $d->fill_element('#peering_servers_table_filter input', 'css', $servername);
    ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr[1]/td[2]', $servername), 'Peering Server has been found');
    $d->move_action(element => $d->find_element('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Preferences")]'));
    $d->find_element('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Preferences")]')->click();

    diag('Open the tab "Number Manipulations"');
    $d->find_element("Number Manipulations", 'link_text')->click();

    diag("Click edit for the preference inbound_upn");
    $d->move_action(element => $d->find_element('//table//td[contains(text(), "inbound_upn")]/..//td//a[contains(text(), "Edit")]'));
    $d->find_element('//table//td[contains(text(), "inbound_upn")]/..//td//a[contains(text(), "Edit")]')->click();

    diag('Change to "P-Asserted-Identity');
    $d->find_element('//*[@id="inbound_upn"]/option[@value="pai_user"]')->click();
    $d->find_element('#save', 'css')->click();

    diag('Check if value has been applied');
    ok($d->find_text('Preference inbound_upn successfully updated'), 'Text "Preference inbound_upn successfully updated" appears');
    ok($d->wait_for_text('//table//td[contains(text(), "inbound_upn")]/../td/select/option[@selected="selected"]', "P-Asserted-Identity"), "Value has been applied");

    diag('Open the tab "Remote Authentication"');
    $d->scroll_to_element($d->find_element("Remote Authentication", 'link_text'));
    $d->find_element("Remote Authentication", 'link_text')->click();

    diag('Edit peer_auth_user');
    $d->move_action(element => $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_user")]/../td/div//a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_user")]/../td/div//a[contains(text(), "Edit")]')->click();
    $d->fill_element('//*[@id="peer_auth_user"]', 'xpath', 'peeruser1');
    $d->find_element('#save', 'css')->click();

    diag('Check if peer_auth_user value has been set');
    ok($d->find_text('Preference peer_auth_user successfully updated'), 'Text "Preference peer_auth_user successfully updated" appears');
    $d->find_element("Remote Authentication", 'link_text')->click();
    ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_user")]/../td[4]', 'peeruser1'), 'peer_auth_user value has been set');

    diag('Edit peer_auth_pass');
    $d->move_action(element => $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_pass")]/../td/div//a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_pass")]/../td/div//a[contains(text(), "Edit")]')->click();
    $d->fill_element('//*[@id="peer_auth_pass"]', 'xpath', 'peerpass1');
    $d->find_element('#save', 'css')->click();

    diag('Check if peer_auth_pass value has been set');
    ok($d->find_text('Preference peer_auth_pass successfully updated'), 'Text "Preference peer_auth_pass successfully updated" appears');
    $d->find_element("Remote Authentication", 'link_text')->click();
    ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_pass")]/../td[4]', 'peerpass1'), 'peer_auth_pass value has been set');

    diag('Edit peer_auth_realm');
    $d->move_action(element => $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_realm")]/../td/div//a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_realm")]/../td/div//a[contains(text(), "Edit")]')->click();
    $d->fill_element('//*[@id="peer_auth_realm"]', 'xpath', 'testpeering.com');
    $d->find_element('#save', 'css')->click();

    diag('Check if peer_auth_realm value has been set');
    ok($d->find_text('Preference peer_auth_realm successfully updated'), 'Text "Preference peer_auth_realm successfully updated" appears');
    $d->find_element("Remote Authentication", 'link_text')->click();
    ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_realm")]/../td[4]', 'testpeering.com'), 'peer_auth_realm value has been set');

    diag("Go back to Servers/Rules");
    $d->get($server_rules_uri);

    diag('skip was here');
    diag("Delete mytestserver");
    $d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#peering_servers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('#peering_servers_table_filter input', 'css', $servername);
    ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr/td[2]', $servername), "mytestserver was found");
    $d->move_action(element => $d->find_element('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
    $d->find_element('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
    ok($d->find_text("Are you sure?"), 'Delete dialog appears');
    $d->find_element('#dataConfirmOK', 'css')->click();
    ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

    diag("Delete the Outbound Peering Rule");
    $d->fill_element('#PeeringRules_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#PeeringRules_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('#PeeringRules_table_filter input', 'css', 'for testing purposes');
    ok($d->wait_for_text('//*[@id="PeeringRules_table"]/tbody/tr/td[5]', 'for testing purposes'), "Outbound Peering Rule was found");
    $d->move_action(element => $d->find_element('//*[@id="PeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
    $d->find_element('//*[@id="PeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
    ok($d->find_text("Are you sure?"), 'Delete dialog appears');
    $d->find_element('#dataConfirmOK', 'css')->click();
    ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

    diag("Delete the Inbound Peering Rule");
    $d->scroll_to_element($d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]'));
    $d->fill_element('#InboundPeeringRules_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#InboundPeeringRules_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('#InboundPeeringRules_table_filter input', 'css', 'forbidden');
    ok($d->wait_for_text('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[6]', 'forbidden'), "Inbound Peering Rule was found");
    $d->move_action(element => $d->find_element('//*[@id="InboundPeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
    $d->find_element('//*[@id="InboundPeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
    ok($d->find_text("Are you sure?"), 'Delete dialog appears');
    $d->find_element('#dataConfirmOK', 'css')->click();
    ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

    diag('Go back to "SIP Peering Groups".');
    $d->get($peerings_uri);

    diag('Delete Testing Group');
    $d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
    ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Testing Group was found');
    $d->move_action(element=> $d->find_element('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
    $d->find_element('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
    ok($d->find_text("Are you sure?"), 'Delete dialog appears');
    $d->find_element('#dataConfirmOK', 'css')->click();
    ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

    diag('Checking if Testing Group has been deleted');
    $d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
    ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Testing Group was deleted');

    return 1;
}

sub ctr_reseller {
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
        browser_name => $browsername,
        extra_capabilities => {
            acceptInsecureCerts => \1,
        },
        port => '5555'
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $resellername = ("reseller" . int(rand(100000)) . "test");
    my $contractid = ("contract" . int(rand(100000)) . "test");
    my $templatename = ("template" . int(rand(100000)) . "mail");

    $c->login_ok();
    $c->create_reseller_contract($contractid);
    $c->create_reseller($resellername, $contractid);

    diag("Check if invalid reseller will be rejected");
    $d->find_element('Create Reseller', 'link_text')->click();
    $d->find_element('#save', 'css')->click();
    ok($d->find_text("Contract field is required"), 'Error "Contract field is required" appears');
    ok($d->find_text("Name field is required"), 'Error "Name field is required" appears');
    $d->find_element('#mod_close', 'css')->click();

    diag("Search our new reseller");
    $d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('#Resellers_table_filter label input', 'css', $resellername);

    diag("Check Reseller Details");
    ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');

    diag("Click Edit on our newly created reseller");
    $d->move_action(element=> $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]'));
    $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]')->click();
    $d->find_element('#mod_close', 'css')->click();

    diag("Click Details on our newly created reseller");
    $d->move_action(element=> $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]'));
    $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]')->click();

    diag("Create a new Invoice Template");
    $d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Invoice Templates")]')->click();
    $d->scroll_to_element($d->find_element("Create Invoice Template", 'link_text'));
    $d->find_element("Create Invoice Template", 'link_text')->click();
    $d->fill_element('//*[@id="name"]', 'xpath', 'testtemplate');
    $d->find_element('//*[@id="save"]')->click();

    diag("Check if Invoice Template has been created");
    $d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Invoice Templates")]')->click();
    $d->scroll_to_element($d->find_element("Create Invoice Template", 'link_text'));
    $d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#InvoiceTemplate_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="InvoiceTemplate_table_filter"]/label/input', 'xpath', 'testtemplate');
    ok($d->wait_for_text('//*[@id="InvoiceTemplate_table"]/tbody/tr/td[2]', 'testtemplate'), 'Entry has been found');

    diag("Create a new Phonebook entry");
    $d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
    $d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
    $d->find_element("Create Phonebook Entry", 'link_text')->click();
    $d->fill_element('//*[@id="name"]', 'xpath', 'TestName');
    $d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
    $d->find_element('//*[@id="save"]')->click();

    diag("Searching Phonebook entry");
    $d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
    $d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
    $d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', '0123456789');

    diag("Checking Phonebook entry details");
    ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[2]', 'TestName'), 'Name is correct');
    ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[3]', '0123456789'), 'Number is correct');

    diag('Go to Email Templates');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Email Templates", 'link_text')->click();

    diag('Trying to create new Template');
    $d->find_element("Create Email Template", 'link_text')->click();
    $d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
    $d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
    $d->fill_element('//*[@id="name"]', 'xpath', $templatename);
    $d->fill_element('//*[@id="from_email"]', 'xpath', 'default@mail.test');
    $d->fill_element('//*[@id="subject"]', 'xpath', 'Testing Stuff');
    $d->fill_element('//*[@id="body"]', 'xpath', 'Howdy Buddy, this is just a test text =)');
    $d->fill_element('//*[@id="attachment_name"]', 'xpath', 'Random Character');
    $d->find_element('//*[@id="save"]')->click();

    diag('Searching new Template');
    $d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);

    diag('Check Details of Template');
    ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[3]', $templatename), "Name is correct");
    ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[2]', $resellername), "Reseller is correct");
    ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[4]', 'default@mail.test'), "From Email is correct");
    ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[5]', 'Testing Stuff'), "Subject is correct");

    diag('Delete Template Email');
    $d->move_and_click('//*[@id="email_template_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath');
    $d->find_element('//*[@id="dataConfirmOK"]')->click();

    diag('Check if Template Email was deleted');
    $d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);
    ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Template was deleted');

    diag("Open delete dialog and press cancel");
    $c->delete_reseller_contract($contractid, 1);
    $d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
    ok($d->wait_for_text('//*[@id="contract_table"]/tbody/tr[1]/td[2]', $contractid), 'Reseller contract is still here');

    diag('Open delete dialog and press delete');
    $c->delete_reseller_contract($contractid, 0);
    $d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
    ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty'), 'Reseller contract was deleted');

    diag("Open delete dialog and press cancel");
    $c->delete_reseller($resellername, 1);
    $d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
    ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller is still here');

    diag('Open delete dialog and press delete');
    $c->delete_reseller($resellername, 0);
    $d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
    ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty'), 'Reseller was deleted');

    return 1;
}

sub ctr_rw_ruleset {
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
        browser_name => $browsername,
        extra_capabilities => {
            acceptInsecureCerts => \1,
        },
        port => '6666'
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $resellername = ("reseller" . int(rand(100000)) . "test");
    my $contractid = ("contract" . int(rand(100000)) . "test");
    my $rulesetname = ("rule" . int(rand(100000)) . "test");
    my $domainstring = ("domain" . int(rand(100000)) . ".example.org");

    $c->login_ok();
    $c->create_reseller_contract($contractid);
    $c->create_reseller($resellername, $contractid);
    $c->create_rw_ruleset($rulesetname, $resellername);

    diag('Search for our new Rewrite Rule Set');
    $d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset was found');

    diag('Create a new Rule for Caller');
    $d->move_action(element => $d->find_element('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Rules")]'));
    $d->find_element('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Rules")]')->click();
    $d->find_element('Create Rewrite Rule', 'link_text')->click;
    $d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
    $d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\2');
    $d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
    $d->find_element('//*[@id="field.1"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if Rule has been created');
    $d->find_element('Inbound Rewrite Rules for Caller', 'link_text')->click();
    ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "International to E.164")]'), "Description is correct");

    diag('Create a new Rule for Callee');
    $d->find_element('Create Rewrite Rule', 'link_text')->click;
    $d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
    $d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\2');
    $d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
    $d->find_element('//*[@id="field.0"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if Rule has been created');
    $d->find_element('Inbound Rewrite Rules for Callee', 'link_text')->click();
    ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "International to E.164")]'), "Description is correct");

    diag('Testing if rules can be reordered');
    diag('Create a new rule for Caller');
    $d->find_element('Create Rewrite Rule', 'link_text')->click;
    $d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
    $d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\1');
    $d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
    $d->find_element('//*[@id="field.1"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Test if new entry moves up if up arrow is clicked');
    $d->find_element('Inbound Rewrite Rules for Caller', 'link_text')->click();
    $d->find_element('//*[@id="collapse_icaller"]/div/table/tbody/tr/td[contains(text(), "\1")]/../td//a//i[@class="icon-arrow-up"]')->click();
    ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]/td[contains(text(), "\1")]'), "Replacement Pattern is correct");

    diag('Trying to add the ruleset to a domain');
    $c->create_domain($domainstring, $resellername);

    diag('Enter Domain Preferences');
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
    ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr/td[3]', $domainstring), 'Entry was found');
    $d->move_action(element => $d->find_element('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Preferences")]'));
    $d->find_element('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Preferences")]')->click();

    diag('Add ruleset to a domain');
    $d->find_element('Number Manipulations', 'link_text')->click;
    $d->move_action(element => $d->find_element('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td/div//a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td/div//a[contains(text(), "Edit")]')->click();
    $d->find_element('//*[@id="rewrite_rule_set.1"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if correct ruleset has been selected');
    $d->find_element('Number Manipulations', 'link_text')->click;

    ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td[4]/select/option[@selected="selected"]', $rulesetname), 'rewrite_rule_set value has been set');

    diag("Open delete dialog and press cancel");
    $c->delete_rw_ruleset($rulesetname, 1);
    $d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset is still here');

    diag('Open delete dialog and press delete');
    $c->delete_rw_ruleset($rulesetname, 0);
    $d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Ruleset was deleted');

    $c->delete_domain($domainstring);
    $c->delete_reseller_contract($contractid);
    $c->delete_reseller($resellername);

    return 1;
}

sub crt_subscriber {
    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
        browser_name => $browsername,
        extra_capabilities => {
            acceptInsecureCerts => \1,
        },
        port => '7777'
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $customerid = ("id" . int(rand(100000)) . "ok");
    my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
    my $emailstring = ("test" . int(rand(10000)) . "\@example.org");
    my $username = ("demo" . int(rand(10000)) . "name");
    my $bsetname = ("test" . int(10000) . "bset");
    my $destinationname = ("test" . int(10000) . "dset");
    my $sourcename = ("test" . int(10000) . "source");

    $c->login_ok();
    $c->create_domain($domainstring);
    $c->create_customer($customerid);

    diag("Open Details for our just created Customer");
    $d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
    $d->fill_element('#Customer_table_filter input', 'css', $customerid);
    ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $customerid), 'Customer found');
    $d->move_action(element=> $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]'));
    $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]')->click();

    diag("Trying to add a Subscriber");
    $d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Subscribers")]')->click();
    $d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Subscribers")]'));
    $d->find_element('Create Subscriber', 'link_text')->click();

    diag('Enter necessary information');
    $d->fill_element('//*[@id="domainidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#domainidtable tr > td.dataTables_empty'), 'Table is empty');
    $d->fill_element('//*[@id="domainidtable_filter"]/label/input', 'xpath', $domainstring);
    ok($d->wait_for_text('//*[@id="domainidtable"]/tbody/tr[1]/td[3]', $domainstring), 'Domain found');
    $d->select_if_unselected('//*[@id="domainidtable"]/tbody/tr[1]/td[4]/input');
    $d->find_element('//*[@id="e164.cc"]')->send_keys('43');
    $d->find_element('//*[@id="e164.ac"]')->send_keys('99');
    $d->find_element('//*[@id="e164.sn"]')->send_keys(int(rand(99999999)));
    $d->find_element('//*[@id="email"]')->send_keys($emailstring);
    $d->find_element('//*[@id="webusername"]')->send_keys($username);
    $d->find_element('//*[@id="webpassword"]')->send_keys('testing1234'); #workaround for misclicking on ok button
    $d->find_element('//*[@id="gen_password"]')->click();
    $d->find_element('//*[@id="username"]')->send_keys($username);
    $d->find_element('//*[@id="password"]')->send_keys('testing1234'); #using normal pwd, cant easily seperate both generate buttons
    $d->find_element('//*[@id="save"]')->click();

    diag('Trying to find Subscriber');
    $d->fill_element('//*[@id="subscribers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#subscribers_table tr > td.dataTables_empty'), 'Table is empty');
    $d->fill_element('//*[@id="subscribers_table_filter"]/label/input', 'xpath', $username);
    ok($d->wait_for_text('//*[@id="subscribers_table"]/tbody/tr/td[2]', $username), 'Subscriber was found');

    diag('Go to Subscribers page');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Subscribers", 'link_text')->click();

    diag('Checking Subscriber Details');
    $d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
    $d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
    ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[3]', 'default-customer@default.invalid'), 'Contact Email is correct');
    ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[4]', $username), 'Subscriber name is correct');
    ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[5]', $domainstring), 'Domain name is correct');

    diag('Go to Subscriber details');
    $d->move_action(element => $d->find_element('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Details")]'));
    $d->find_element('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Details")]')->click();

    diag('Go to Subscriber preferences');
    $d->find_element("Preferences", 'link_text')->click();

    diag('Trying to change subscriber IVR language');
    $d->find_element("Internals", 'link_text')->click();
    $d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "language")]'));
    $d->move_and_click('//table//tr/td[contains(text(), "language")]/..//td//a[contains(text(), "Edit")]', 'xpath');

    diag('Change language to German');
    $d->find_element('//*[@id="language"]/option[contains(text(), "German")]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if language has been applied');
    $d->scroll_to_element($d->find_element('//*[@id="preference_groups"]//div//a[contains(text(),"Internals")]'));
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "language")]/../td/select/option[contains(text(), "German") and @selected="selected"]'), '"German" has been selected');

    diag('Trying to enable call recording');
    $d->find_element("NAT and Media Flow Control", 'link_text')->click();
    $d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "record_call")]'));
    $d->move_and_click('//table//tr/td[contains(text(), "record_call")]/..//td//a[contains(text(), "Edit")]', 'xpath');

    diag('Enable call recording');
    $d->select_if_unselected('//*[@id="record_call"]');
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if call recording was enabled');
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "record_call")]/../td//input[@checked="checked"]'), "Call recording was enabled");

    diag('Trying to add a simple call forward');
    $d->find_element("Call Forwards", 'link_text')->click();
    $d->move_and_click('//*[@id="preferences_table_cf"]/tbody/tr/td[contains(text(), "Unconditional")]/../td/div/a[contains(text(), "Edit")]', 'xpath');
    $d->fill_element('//*[@id="destination.uri.destination"]', 'xpath', '43123456789');
    $d->find_element('//*[@id="cf_actions.advanced"]')->click();

    diag('Add a new Source set');
    $d->find_element('//*[@id="cf_actions.edit_source_sets"]')->click();
    $d->find_element('Create New', 'link_text')->click();
    $d->fill_element('//*[@id="name"]', 'xpath', $sourcename);
    $d->fill_element('//*[@id="source.0.source"]', 'xpath', '43*');

    diag('Adding another source');
    $d->find_element('//*[@id="source_add"]')->click();
    ok($d->fill_element('//*[@id="source.1.source"]', 'xpath', '494331337'), "New Source input was created");
    $d->find_element('//*[@id="save"]')->click();

    diag('Check Source set details');
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $sourcename . '")]'), "Name is correct");
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $sourcename . '")]/../td[contains(text(), "whitelist")]'), "Mode is correct");
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $sourcename . '")]/../td[contains(text(), "43*")]'), "Number 1 is correct");
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $sourcename . '")]/../td[text()[contains(., "494331337")]]'), "Number 2 is correct");
    $d->find_element('//*[@id="mod_close"]')->click();

    diag('Add a new B-Number set');
    $d->find_element('//*[@id="cf_actions.edit_bnumber_sets"]')->click();
    $d->find_element('Create New', 'link_text')->click();
    $d->fill_element('//*[@id="name"]', 'xpath', $bsetname);
    $d->fill_element('//*[@id="bnumbers.0.number"]', 'xpath', '1234567890');
    $d->find_element('//*[@id="save"]')->click();

    diag('Check B-Number set details');
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $bsetname . '")]'), "Name is correct");
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $bsetname . '")]/../td[contains(text(), "1234567890")]'), "Number is correct");
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $bsetname . '")]/../td[contains(text(), "whitelist")]'), "Mode is correct");
    $d->find_element('//*[@id="mod_close"]')->click();

    diag('Add a new Destination set');
    $d->find_element('//*[@id="cf_actions.edit_destination_sets"]')->click();
    $d->find_element('Create New', 'link_text')->click();
    $d->fill_element('//*[@id="name"]', 'xpath', $destinationname);
    $d->fill_element('//*[@id="destination.0.uri.destination"]', 'xpath', '1234567890');
    $d->find_element('//*[@id="save"]')->click();

    diag('Check Destination set details');
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $destinationname . '")]'), "Name is correct");
    ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $destinationname . '")]/../td[contains(text(), "1234567890")]'), "Number is correct");
    $d->find_element('//*[@id="mod_close"]')->click();

    diag('Use new Sets');
    $d->find_element('//*[@id="callforward_controls_add"]')->click();
    $d->find_element('//*[@id="active_callforward.0.source_set"]/option[contains(text(), "' . $sourcename . '")]')->click();
    ok($d->find_element_by_xpath('//select//option[contains(text(), "' . $sourcename . '")]')->click(), "Source set has been found");
    ok($d->find_element_by_xpath('//select//option[contains(text(), "' . $destinationname . '")]')->click(), "Destination Set has been found");
    ok($d->find_element_by_xpath('//select//option[contains(text(), "' . $bsetname . '")]')->click(), "B-Set has been found");

    diag('Save');
    $d->find_element('//*[@id="cf_actions.save"]')->click();

    diag('Check if call-forward has been applied');
    ok($d->find_element_by_xpath('//*[@id="preferences_table_cf"]/tbody/tr[1]/td[contains(text(), ' . $bsetname . ')]'), 'B-Set was selected');
    ok($d->find_element_by_xpath('//*[@id="preferences_table_cf"]/tbody/tr[1]/td[contains(text(), ' . $destinationname . ')]'), 'Destination set was selected');

    diag('Trying to add call blockings');
    $d->find_element("Call Blockings", 'link_text')->click();
    $d->scroll_to_element($d->find_element("Call Blockings", 'link_text'));

    diag('Edit block_in_mode');
    $d->move_and_click('//table//tr/td[contains(text(), "block_in_mode")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
    $d->find_element('//*[@id="block_in_mode"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if value was set');
    $d->scroll_to_element($d->find_element("Call Blockings", 'link_text'));
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_mode")]/../td/input[@checked="checked"]'), "Setting is correct");

    diag('Edit block_in_list');
    $d->move_and_click('//table//tr/td[contains(text(), "block_in_list")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
    $d->fill_element('//*[@id="block_in_list"]', 'xpath', '1337');
    $d->find_element('//*[@id="add"]')->click();
    $d->fill_element('//*[@id="block_in_list"]', 'xpath', '42');
    $d->find_element('//*[@id="add"]')->click();
    $d->find_element('//*[@id="mod_close"]')->click();

    diag('Check if value was set');
    $d->scroll_to_element($d->find_element("Call Blockings", 'link_text'));
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_list")]/../td[contains(text(), "1337")]'), "Number 1 is correct");
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_list")]/../td[text()[contains(., "42")]]'), "Number 2 is correct");

    diag('Disable Entry');
    $d->move_and_click('//table//tr/td[contains(text(), "block_in_list")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
    $d->find_element('//*[@id="mod_edit"]//div//input[@value="1337"]/../a[2]')->click();
    $d->find_element('//*[@id="mod_close"]')->click();

    diag('Check if Entry was disabled');
    $d->scroll_to_element($d->find_element("Call Blockings", 'link_text'));
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_list")]/../td/span[@class="ngcp-entry-disabled"]/../span[contains(text(), "1337")]'), "Entry was disabled");

    diag('Edit block_in_clir');
    $d->move_and_click('//table//tr/td[contains(text(), "block_in_clir")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
    $d->find_element('//*[@id="block_in_clir"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if value was set');
    ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_clir")]/../td/input[@checked="checked"]'), "Setting is correct");

    diag('Go to Subscribers Page');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Subscribers", 'link_text')->click();

    diag('Trying to delete Subscriber');
    $d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
    $d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
    ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[4]', $username), 'Subscriber was found');
    $d->move_action(element => $d->find_element('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Terminate")]'));
    $d->find_element('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Terminate")]')->click();
    $d->find_element('//*[@id="dataConfirmOK"]')->click();

    diag('Check if Subscriber has been deleted');
    $d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
    ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');

    $c->delete_customer($customerid);
    $c->delete_domain($domainstring);

    return 1;
}
1;