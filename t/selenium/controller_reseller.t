use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
);

my $c = Selenium::Collection::Common->new(
    driver => $d
);

my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag("Check if invalid reseller will be rejected");
$d->find_element('Create Reseller', 'link_text')->click();
$d->find_element('#save', 'css')->click();
ok($d->find_text("Contract field is required"), 'Error "Contract field is required" appears');
ok($d->find_text("Name field is required"), 'Error "Name field is required" appears');
$d->find_element('#mod_close', 'css')->click();

$c->create_reseller();

diag("Search our new reseller");
$d->fill_element('#Resellers_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#Resellers_table_filter label input', 'css', $resellername);

diag("Check Reseller Details");
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller Name is correct');
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[2]', $contractid), 'Contract ID is correct');

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

diag("Go back to previous page");
$d->find_element("Back", 'link_text')->click();

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

done_testing;
# vim: filetype=perl
