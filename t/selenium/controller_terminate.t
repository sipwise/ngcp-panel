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

my $customerid = ("id" . int(rand(100000)) . "ok");
my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $contactmail = ("contact" . int(rand(100000)) . '@test.org');
my $billingname = ("billing" . int(rand(100000)) . "test");
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $username = ("demo" . int(rand(10000)) . "name");
my $run_ok = 0;
my $custnum;
my $compstring;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_domain($domainstring, $resellername);
$c->create_contact($contactmail, $resellername);
$c->create_billing_profile($billingname, $resellername);
$c->create_customer($customerid, $contactmail, $billingname);

diag("Go to 'Customers' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Customers', 'link_text')->click();

diag("Create Subscriber for Termination Test");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Customer found');
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Customer_table_filter"]//input');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Subscribers")]'));
$d->find_element('Create Subscriber', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Subscriber")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="domainidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#domainidtable tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="domainidtable_filter"]/label/input', 'xpath', $domainstring);
ok($d->find_element_by_xpath('//*[@id="domainidtable"]//tr[1]/td[contains(text(), "' . $domainstring . '")]'), 'Domain found');
$d->select_if_unselected('//*[@id="domainidtable"]/tbody/tr[1]/td[4]/input');
$d->find_element('//*[@id="username"]')->send_keys($username);
$d->find_element('//*[@id="password"]')->send_keys('testing1234');
$d->find_element('//*[@id="save"]')->click();

diag("Go to 'Subscribers' page");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber successfully created',  'Correct Alert was shown');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Subscribers', 'link_text')->click();

diag("Terminate Subscriber");
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->find_element_by_xpath('//*[@id="subscriber_table"]//tr[1]/td[contains(text(), "' . $username . '")]'), 'Subscriber was found');
$d->move_and_click('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Details")]', 'xpath', '//*[@id="subscriber_table_filter"]//input');
$d->find_element('//*[@id="subscriber_data"]//div//a[contains(text(), "Master Data")]')->click();
$d->find_element('//*[@id="collapse_master"]/div/a[contains(text(), "Edit")]')->click();
$d->find_element('//*[@id="status"]/option[@value="terminated"]')->click();
$d->find_element('//*[@id="save"]')->click();
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")][contains(text(), "Subscriber does not exist")]'), 'Correct Alert was shown');

diag("Check if Subscriber has been terminated");
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Subscriber has been terminated');

diag("Go to 'Customers' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Customers', 'link_text')->click();

diag("Edit Customer");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Found customer');
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Customer_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Customer")]'), 'Edit window has been opened');
$d->find_element('//*[@id="status"]/option[@value="locked"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Customer was edited");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "' . $customerid . '")]'), 'Found customer');
ok($d->find_element_by_xpath('//*[@id="Customer_table"]//tr[1]/td[contains(text(), "locked")]'), 'Status was changed');
$custnum = $d->get_text('//*[@id="Customer_table"]//tr[1]//td[1]');
$compstring = "Customer #" . $custnum . " successfully updated";
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), $compstring,  'Correct Alert was shown');

diag("Edit Customer status to 'terminated'");
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Customer_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Customer")]'), 'Edit window has been opened');
$d->scroll_to_element($d->find_element('//*[@id="status"]'));
$d->find_element('//*[@id="status"]/option[@value="terminated"]')->click();
$d->find_element('#save', 'css')->click();

diag("Check if Customer was terminated");
$compstring = "Customer #" . $custnum . " successfully updated";
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), $compstring,  'Correct Alert was shown');
$d->fill_element('//*[@id="Customer_table_filter"]/label/input', 'xpath', $customerid);
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Customer was terminated');

diag("Go to 'Contacts' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Contacts', 'link_text')->click();

diag("Search Contact");
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contact_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', $contactmail);
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Contact found');

diag("Check if Editing Contact works");
$d->move_and_click('//*[@id="contact_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="contact_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Contact")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="firstname"]', 'xpath', 'TestFistName');
$d->fill_element('//*[@id="lastname"]', 'xpath', 'TestLastName');
$d->fill_element('//*[@id="company"]', 'xpath', 'TestCompany');
$d->find_element('//*[@id="save"]')->click();

diag("Check if Contact was edited");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contact successfully changed',  'Correct Alert was shown');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contact_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('//*[@id="contact_table_filter"]/label/input', 'xpath', $contactmail);
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "' . $contactmail . '")]'), 'Contact found');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "TestFistName")]'), 'First Name was edited');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "TestLastName")]'), 'Last Name was edited');
ok($d->find_element_by_xpath('//*[@id="contact_table"]//tr[1]/td[contains(text(), "TestCompany")]'), 'Company was edited');

$c->delete_contact($contactmail);
$c->delete_domain($domainstring);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("Create default Reseller + Contract for termination testing");
$d->find_element('//*[@id="content"]//div//form//button[contains(text(), "Create Reseller with default values")]')->click();
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "Reseller Details for")]'), 'We are on the correct page');

diag("Get Reseller name");
if($d->find_element_by_xpath('//*[@id="reseller_details"]//div//a[contains(text(), "Reseller Base Information")]/../../../div')->get_attribute('class', 1) eq 'accordion-group') {
    $d->find_element('//*[@id="reseller_details"]//div//a[contains(text(), "Reseller Base Information")]')->click();
}
$resellername = $d->get_text('//*[@id="Reseller_table"]/tbody/tr/td[2]');
my $temp = substr($resellername, 8);
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Reseller successfully created with login Default' . $temp . ' and password defaultresellerpassword, please review your settings below',  'Correct Alert was shown');

diag("Add unique name to Contract");
$contractid = ("contract" . int(rand(100000)) . "term");
sleep 1;
$d->find_element('//*[@id="reseller_details"]//div//a[contains(text(), "Reseller Contract")]')->click();
$d->move_and_click('//*[@id="Contract_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="masthead"]//div//h2[contains(text(), "Reseller Details")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Contract")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="external_id"]', 'xpath', $contractid);
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contract successfully changed!',  'Correct Alert was shown');

diag("Go to 'Reseller Contracts' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Reseller and Peering Contracts', 'link_text')->click();

diag("Search Reseller Contract");
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_xpath('//*[@id="contract_table"]//tr[1]/td[contains(text(), "' . $contractid . '")]'), 'Reseller contract found');

diag("Terminate Reseller Contract");
$d->move_and_click('//*[@id="contract_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="contract_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Contract")]'), 'Edit window has been opened');
$d->scroll_to_element($d->find_element('//*[@id="status"]'));
$d->find_element('//*[@id="status"]/option[@value="terminated"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Reseller Contract was terminated");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contract successfully changed!',  'Correct Alert was shown');
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty', 'css'), 'Reseller Contract was terminated');

diag("Go to 'Resellers' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Resellers', 'link_text')->click();

diag("Search reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller Name is correct');

diag("Terminate Reseller");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Reseller")]'), 'Edit window has been opened');
$d->find_element('//*[@id="status"]/option[@value="terminated"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Reseller has been terminated");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Reseller successfully updated',  'Correct Alert was shown');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Reseller has been terminated');

diag("Create default Reseller + Contract for termination testing");
$d->find_element('//*[@id="content"]//div//form//button[contains(text(), "Create Reseller with default values")]')->click();
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "Reseller Details for")]'), 'We are on the correct page');
diag("Get Reseller name");
if($d->find_element_by_xpath('//*[@id="reseller_details"]//div//a[contains(text(), "Reseller Base Information")]/../../../div')->get_attribute('class', 1) eq 'accordion-group') {
    $d->find_element('//*[@id="reseller_details"]//div//a[contains(text(), "Reseller Base Information")]')->click();
}
$resellername = $d->get_text('//*[@id="Reseller_table"]/tbody/tr/td[2]');
$temp = substr($resellername, 8);
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Reseller successfully created with login Default' . $temp . ' and password defaultresellerpassword, please review your settings below',  'Correct Alert was shown');

diag("Add unique name to Contract");
$contractid = ("contract" . int(rand(100000)) . "term");
sleep 1;
$d->find_element('//*[@id="reseller_details"]//div//a[contains(text(), "Reseller Contract")]')->click();
$d->move_and_click('//*[@id="Contract_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="masthead"]//div//h2[contains(text(), "Reseller Details")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Contract")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="external_id"]', 'xpath', $contractid);
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contract successfully changed!',  'Correct Alert was shown');

diag("Go to 'Resellers' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Resellers', 'link_text')->click();

diag("Search Reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller Name is correct');

diag("Terminate Reseller");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Reseller")]'), 'Edit window has been opened');
$d->find_element('//*[@id="status"]/option[@value="terminated"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Reseller has been terminated");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Reseller successfully updated',  'Correct Alert was shown');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Reseller has been terminated');

diag("Go to 'Reseller Contracts' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Reseller and Peering Contracts', 'link_text')->click();

diag("Check if Reseller Contract has been terminated");
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty', 'css'), 'Reseller Contract has been terminated');

$c->delete_billing_profile($billingname);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_terminate.png");
    }
    $d->quit();
    done_testing;
}