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
$c->create_reseller($resellername, $contractid);

diag("Try to create an empty Reseller");
$d->find_element('Create Reseller', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Reseller")]'), 'Edit window has been opened');
$d->unselect_if_selected('//*[@id="contractidtable"]/tbody/tr/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Contract field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
$d->find_element('#mod_close', 'css')->click();

diag("Search Reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller name is correct');
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "active")]'), 'Status is correct');

diag("Edit Reseller");
$resellername = ("reseller" . int(rand(100000)) . "test");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Reseller")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $resellername);
$d->find_element('//*[@id="status"]/option[@value="locked"]')->click();
$d->find_element('#save', 'css')->click();

diag("Search Reseller");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Reseller successfully updated',  'Correct Alert was shown');
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller name is correct');
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "locked")]'), 'Status is correct');

diag("Go to Customer details and check if 'Reseller is locked' message appears");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "Reseller Details")]'), 'We are on the correct Page');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Reseller is locked',  '"Reseller is locked" message appears');
$d->find_element('Back', 'link_text')->click();

diag("Unlock Reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller was found');
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Reseller")]'), 'Edit window has been opened');
$d->scroll_to_element($d->find_element('//*[@id="status"]'));
$d->find_element('//*[@id="status"]/option[@value="active"]')->click();
$d->find_element('#save', 'css')->click();

diag("Check Reseller details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Reseller successfully updated',  'Correct Alert was shown');
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller name is correct');
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "active")]'), 'Status is correct');

diag("Go to 'Reseller Details' page");
$d->move_and_click('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Resellers_table_filter"]//input');

diag("Create an empty Phonebook entry");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]'));
$d->find_element("Create Phonebook Entry", 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Phonebook")]'), 'Edit window has been opened');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Number field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="name"]', 'xpath', 'testname');
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag("Search Phonebook entry");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully created',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'testname');

diag("Checking Phonebook entry details");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "testname")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "0123456789")]'), 'Number is correct');

diag("Edit Phonebook entry");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="phonebook_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Phonebook")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', 'newtestname');
$d->fill_element('//*[@id="number"]', 'xpath', '0987654321');
$d->find_element('//*[@id="save"]')->click();

diag("Checking Phonebook entry details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Phonebook entry successfully updated',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]'));
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "newtestname")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "0987654321")]'), 'Number is correct');

diag("Go to 'Email Templates' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Email Templates', 'link_text')->click();

diag("Try to create an empty Email Template");
$d->find_element('Create Email Template', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Email Template")]'), 'Edit window has been opened');
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "From Email Address field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Subject field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->fill_element('//*[@id="from_email"]', 'xpath', 'default@mail.test');
$d->fill_element('//*[@id="subject"]', 'xpath', 'Testing Stuff');
$d->fill_element('//*[@id="body"]', 'xpath', 'Howdy Buddy, this is just a test text =)');
$d->fill_element('//*[@id="attachment_name"]', 'xpath', 'Random Character');
$d->find_element('//*[@id="save"]')->click();

diag("Search Email Template");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Email template successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "' . $templatename . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "default@mail.test")]'), 'From Email is correct');
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "Testing Stuff")]'), 'Subject is correct');

diag("Edit Email Template");
$templatename = ("template" . int(rand(100000)) . "mail");
$d->move_and_click('//*[@id="email_template_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Email Template")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $templatename);
$d->fill_element('//*[@id="from_email"]', 'xpath', 'standard@mail.test');
$d->fill_element('//*[@id="subject"]', 'xpath', 'testing much stuff');
$d->fill_element('//*[@id="body"]', 'xpath', 'No seriously, this is just for testing');
$d->fill_element('//*[@id="attachment_name"]', 'xpath', '=)');
$d->find_element('//*[@id="save"]')->click();

diag("Search Email Template");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Email template successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "' . $templatename . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "standard@mail.test")]'), 'From Email is correct');
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "testing much stuff")]'), 'Subject is correct');

diag("Try to NOT delete Email Template");
$d->move_and_click('//*[@id="email_template_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Email Template is still here");
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_xpath('//*[@id="email_template_table"]//tr[1]/td[contains(text(), "' . $templatename . '")]'), 'Email Template is still here');

diag("Delete Email Template");
$d->move_and_click('//*[@id="email_template_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="email_template_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Email Template has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Email template successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="email_template_table_filter"]/label/input', 'xpath', $templatename);
ok($d->find_element_by_css('#email_template_table tr > td.dataTables_empty', 'css'), 'Email Template has been deleted');

diag("Try to NOT delete Reseller Contract");
$c->delete_reseller_contract($contractid, 1);

diag("Check if Reseller Contract is still here");
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_xpath('//*[@id="contract_table"]//tr[1]/td[contains(text(), "' . $contractid . '")]'), 'Reseller contract is still here');

diag("Try to delete Reseller Contract");
$c->delete_reseller_contract($contractid, 0);

diag("Check if Reseller Contract has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Contract successfully terminated',  'Correct Alert was shown');
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty'), 'Reseller contract has been deleted');

diag("Try to NOT delete Reseller");
$c->delete_reseller($resellername, 1);

diag("Check if Reseller is still here");
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="Resellers_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is still here');

diag("Try to delete Reseller");
$c->delete_reseller($resellername, 0);

diag("Check if Reseller has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Successfully terminated reseller',  'Correct Alert was shown');
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty'), 'Reseller has been deleted');

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_reseller.png");
    }
    $d->quit();
    done_testing;
}