use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

my ($port) = @_;
my $d = Selenium::Collection::Functions::create_driver($port);
my $c = Selenium::Collection::Common->new(
    driver => $d
);

my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $templatename = ("template" . int(rand(100000)) . "mail");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);

diag('Go to reseller page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Resellers', 'link_text')->click();

diag('Try to create a empty reseller');
$d->find_element('Create Reseller', 'link_text')->click();
$d->unselect_if_selected('//*[@id="contractidtable"]/tbody/tr/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag('Check Error Messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Contract field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag('Create a legit reseller');
$d->find_element('#mod_close', 'css')->click();
$c->create_reseller($resellername, $contractid);

diag("Search our new reseller");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Reseller successfully created.",  "Correct Alert was shown");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);

diag("Check Reseller Details");
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr//td[contains(text(), "active")]'), 'Status is correct');

diag("Click Edit on our newly created reseller");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');

diag("Edit name and status");
$resellername = ("reseller" . int(rand(100000)) . "test");
$d->fill_element('//*[@id="name"]', 'xpath', $resellername);
$d->find_element('//*[@id="status"]/option[@value="locked"]')->click();
$d->find_element('#save', 'css')->click();

diag("Search our new reseller");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Reseller successfully updated",  "Correct Alert was shown");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);

diag("Check Reseller Details");
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr//td[contains(text(), "locked")]'), 'Status is correct');

diag("Go to Details and check if 'Reseller is locked' message appears");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "Reseller Details")]'), "We are on the correct Page");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Reseller is locked",  "'Reseller is locked' message appears");
$d->find_element("Back", 'link_text')->click();

diag("Unlock reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller was found');
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');
$d->scroll_to_element($d->find_element('//*[@id="status"]'));
$d->find_element('//*[@id="status"]/option[@value="active"]')->click();
$d->find_element('#save', 'css')->click();

diag("Check Reseller Details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Reseller successfully updated",  "Correct Alert was shown");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr//td[contains(text(), "active")]'), 'Status is correct');

diag("Go to Reseller Details");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');

diag("Create a empty Phonebook entry");
$d->scroll_to_element($d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]'));
$d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
$d->find_element("Create Phonebook Entry", 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Number field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="name"]', 'xpath', 'testname');
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag("Searching Phonebook entry");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Phonebook entry successfully created",  "Correct Alert was shown");
$d->scroll_to_element($d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]'));
$d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'testname');

diag("Checking Phonebook entry details");
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[2]', 'testname'), 'Name is correct');
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[3]', '0123456789'), 'Number is correct');

diag("Edit Phonebook entry");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="phonebook_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', 'newtestname');
$d->fill_element('//*[@id="number"]', 'xpath', '0987654321');
$d->find_element('//*[@id="save"]')->click();

diag("Searching Phonebook entry");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Phonebook entry successfully updated",  "Correct Alert was shown");
$d->scroll_to_element($d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]'));
$d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'newtestname');

diag("Checking Phonebook entry details");
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[2]', 'newtestname'), 'Name is correct');
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[3]', '0987654321'), 'Number is correct');

diag('Go to Email Templates');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Email Templates", 'link_text')->click();

diag('Trying to create a empty Template');
$d->find_element("Create Email Template", 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag('Check Error Messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "From Email Address field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Subject field is required")]'));

diag('Fill in values');
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
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Email template successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);

diag('Check Details of Template');
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[3]', $templatename), "Name is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[4]', 'default@mail.test'), "From Email is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[5]', 'Testing Stuff'), "Subject is correct");

diag('Edit Email Template');
$templatename = ("template" . int(rand(100000)) . "mail");
$d->move_and_click('//*[@id="email_template_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->fill_element('//*[@id="from_email"]', 'xpath', 'standard@mail.test');
$d->fill_element('//*[@id="subject"]', 'xpath', 'testing much stuff');
$d->fill_element('//*[@id="body"]', 'xpath', 'No seriously, this is just for testing');
$d->fill_element('//*[@id="attachment_name"]', 'xpath', '=)');
$d->find_element('//*[@id="save"]')->click();

diag('Searching new Template');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Email template successfully updated",  "Correct Alert was shown");
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);

diag('Check Details of Template');
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[3]', $templatename), "Name is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[4]', 'standard@mail.test'), "From Email is correct");
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[5]', 'testing much stuff'), "Subject is correct");

diag('Try to NOT delete Email Template');
$d->move_and_click('//*[@id="email_template_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Template Email is still here');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);
ok($d->wait_for_text('//*[@id="email_template_table"]/tbody/tr/td[3]', $templatename), "Template is still here");

diag('Delete Template Email');
$d->move_and_click('//*[@id="email_template_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Template Email was deleted');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Email template successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Template was deleted');

diag("Open delete dialog and press cancel");
$c->delete_reseller_contract($contractid, 1);
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->wait_for_text('//*[@id="contract_table"]/tbody/tr[1]/td[2]', $contractid), 'Reseller contract is still here');

diag('Open delete dialog and press delete');
$c->delete_reseller_contract($contractid, 0);
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Contract successfully terminated",  "Correct Alert was shown");
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty'), 'Reseller contract was deleted');

diag("Open delete dialog and press cancel");
$c->delete_reseller($resellername, 1);
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller is still here');

diag('Open delete dialog and press delete');
$c->delete_reseller($resellername, 0);
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Successfully terminated reseller",  "Correct Alert was shown");
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty'), 'Reseller was deleted');

diag('Create default Reseller + Contract for termination testing');
$d->find_element('//*[@id="content"]//div//form//button[contains(text(), "Create Reseller with default values")]')->click();
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "Reseller Details for")]'), "We are on the correct page");
diag('Get Reseller Name');
if($d->find_element_by_xpath('//*[@id="reseller_details"]//div//a[contains(text(), "Reseller Base Information")]/../../../div')->get_attribute('class', 1) eq 'accordion-group') {
    $d->find_element('//*[@id="reseller_details"]//div//a[contains(text(), "Reseller Base Information")]')->click();
}
$resellername = $d->get_text('//*[@id="Reseller_table"]/tbody/tr/td[2]');
#is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Reseller successfully created with login " . $resellername . " and password defaultresellerpassword, please review your settings below",  "Correct Alert was shown");
$d->find_element('//*[@id="content"]//div//a[contains(text(), "Back")]')->click();

diag('Get Contract Number');
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');
$contractid = $d->get_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[2]');

diag("Go to Reseller Contracts");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Reseller and Peering Contracts', 'link_text')->click();

diag("Search for Reseller Contract");
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->wait_for_text('//*[@id="contract_table"]/tbody/tr[1]/td[1]', $contractid), 'Reseller contract found');

diag("Terminate Reseller Contract");
$d->move_and_click('//*[@id="contract_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="contract_table_filter"]/label/input');
$d->scroll_to_element($d->find_element('//*[@id="status"]'));
$d->find_element('//*[@id="status"]/option[@value="terminated"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Reseller Contract was terminated");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Contract successfully changed!",  "Correct Alert was shown");
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty', 'css'), 'Reseller Contract was terminated');

diag("Go to Reseller");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Resellers', 'link_text')->click();

diag("Search reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');

diag("Terminate Reseller");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');
$d->find_element('//*[@id="status"]/option[@value="terminated"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Reseller was terminated");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Reseller successfully updated",  "Correct Alert was shown");
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Reseller was deleted');

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_reseller.png");
    }
    $d->quit();
    done_testing;
}