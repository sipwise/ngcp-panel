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

my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $soundsetname = ("sound" . int(rand(100000)) . "set");
my $phonebookname = ("phone" . int(rand(100000)) . "book");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_domain($domainstring);

diag('Go to Call List Suppressions');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Call List Suppressions", 'link_text')->click();

diag('Trying to create a empty call list suppression');
$d->find_element("Create call list suppression", "link_text")->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check error messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Pattern field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Label field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="domain"]', 'xpath', $domainstring);
$d->fill_element('//*[@id="pattern"]', 'xpath', 'test');
$d->fill_element('//*[@id="label"]', 'xpath', 'label');
$d->find_element('//*[@id="save"]')->click();

diag('Search Call list suppression');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Call list suppression successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#call_list_suppression_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', $domainstring);

diag('Check details');
ok($d->wait_for_text('//*[@id="call_list_suppression_table"]//tr[1]/td[2]', $domainstring), "Label is correct");
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "outgoing")]'), 'Direction is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "test")]'), 'Pattern is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "filter")]'), 'Mode is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "label")]'), 'Label is correct');

diag('Edit Call list suppression');
$d->move_and_click('//*[@id="call_list_suppression_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="call_list_suppression_table_filter"]//input');
$d->find_element('//*[@id="direction"]/option[@value="incoming"]')->click();
$d->fill_element('//*[@id="pattern"]', 'xpath', 'testing');
$d->find_element('//*[@id="mode"]/option[@value="obfuscate"]')->click();
$d->fill_element('//*[@id="label"]', 'xpath', 'text');
$d->find_element('//*[@id="save"]')->click();

diag('Search Call list suppression');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Call list suppression successfully updated",  "Correct Alert was shown");
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#call_list_suppression_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', $domainstring);

diag('Check details');
ok($d->wait_for_text('//*[@id="call_list_suppression_table"]//tr[1]/td[2]', $domainstring), "Label is correct");
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "incoming")]'), 'Direction is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "testing")]'), 'Pattern is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "obfuscate")]'), 'Mode is correct');
ok($d->find_element_by_xpath('//*[@id="call_list_suppression_table"]//tr[1]/td[contains(text(), "text")]'), 'Label is correct');

diag('Trying to NOT delete Call list suppression');
$d->move_and_click('//*[@id="call_list_suppression_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="call_list_suppression_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Call list suppression is still here');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#call_list_suppression_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->wait_for_text('//*[@id="call_list_suppression_table"]//tr[1]/td[2]', $domainstring), "Call list suppression is still here");

diag('Trying to delete Call list suppression');
$d->move_and_click('//*[@id="call_list_suppression_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="call_list_suppression_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Call list suppression was deleted');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Call list suppression successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="call_list_suppression_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->find_element_by_css('#call_list_suppression_table tr > td.dataTables_empty', 'css'), 'Call list suppression has been deleted');

diag('Go to Phonebook');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Phonebook", 'link_text')->click();

diag('Trying to create a empty Phonebook entry');
$d->find_element('Create Phonebook Entry', 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag('Check error messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Number field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $phonebookname);
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag('Search for Phonebook entry');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Phonebook entry successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', $phonebookname);

diag('Check details');
ok($d->wait_for_text('//*[@id="phonebook_table"]//tr[1]/td[3]', $phonebookname), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "0123456789")]'), 'Number is correct');

diag('Edit Phonebook entry');
my $phonebookname = ("phone" . int(rand(100000)) . "book");
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="phonebook_table_filter"]//input');
$d->fill_element('//*[@id="name"]', 'xpath', $phonebookname);
$d->fill_element('//*[@id="number"]', 'xpath', '9876543210');
$d->find_element('//*[@id="save"]')->click();

diag('Search for Phonebook entry');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Phonebook entry successfully updated",  "Correct Alert was shown");
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', $phonebookname);

diag('Check details');
ok($d->wait_for_text('//*[@id="phonebook_table"]//tr[1]/td[3]', $phonebookname), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="phonebook_table"]//tr[1]/td[contains(text(), "9876543210")]'), 'Number is correct');

diag('Trying to NOT delete Phonebook entry');
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="phonebook_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Phonebook entry is still here');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', $phonebookname);
ok($d->wait_for_text('//*[@id="phonebook_table"]//tr[1]/td[3]', $phonebookname), "Phonebook entry is still here");

diag('Trying to delete Phonebook entry');
$d->move_and_click('//*[@id="phonebook_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="phonebook_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Phonebook entry has been deleted');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Phonebook entry successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="phonebook_table_filter"]//input', 'xpath', $phonebookname);
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Phonebook entry has been deleted');

$c->delete_domain($domainstring);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_header.png");
    }
    done_testing;
}