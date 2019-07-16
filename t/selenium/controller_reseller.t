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

$d->login_ok();

my $resellername = ("test" . int(rand(10000)));
my $contractid = ("test" . int(rand(10000)));
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag("Check if invalid reseller will be rejected");
$d->find_element('Create Reseller', 'link_text')->click();
$d->find_element('#save', 'css')->click();
ok($d->find_text("Contract field is required"), 'Error "Contract field is required" appears');
ok($d->find_text("Name field is required"), 'Error "Name field is required" appears');
$d->find_element('#mod_close', 'css')->click();

$c->create_reseller();

diag("Search nonexisting reseller");
my $searchfield = $d->find_element('#Resellers_table_filter label input', 'css');
$searchfield->send_keys('thisshouldnotexist');

diag("Verify that nothing is shown");
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$searchfield->clear();

diag("Search for our newly created reseller");
$searchfield->send_keys($resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Our new reseller was found');

diag("Click Edit on our newly created reseller");
$d->move_action(element=> $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]'));
$d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]//td//div//a[contains(text(),"Edit")]')->click();
$d->find_element('#mod_close', 'css')->click();

diag("Search nonexisting reseller");
$searchfield->send_keys('thisshouldnotexist');

diag("Verify that nothing is shown");
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$searchfield->clear();

diag("Search for our newly created reseller");
$searchfield->send_keys($resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Our new reseller was found');

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
$d->fill_element('//*[@id="name"]', 'xpath', 'Test Name');
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag("Check if Phonebook Entry has been created");
$d->find_element('//*[@id="reseller_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', '0123456789');
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[3]', '0123456789'), 'Entry has been found');

diag("Go back to previous page");
$d->find_element("Back", 'link_text')->click();

diag("Press cancel on delete dialog to check if reseller contract is still there");
$c->delete_reseller_contract($contractid, 1);
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->wait_for_text('//*[@id="contract_table"]/tbody/tr[1]/td[2]', $contractid), 'Reseller contract is still here');

diag("Now deleting the reseller contract");
$c->delete_reseller_contract($contractid);
$d->fill_element('//*[@id="contract_table_filter"]/label/input', 'xpath', $contractid);
ok($d->find_element_by_css('#contract_table tr > td.dataTables_empty'), 'Reseller contract was deleted');

diag("Press cancel on delete dialog to check if reseller is still there");
$c->delete_reseller($resellername, 1);
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]', $resellername), 'Reseller contract is still here');

diag("Now deleting the reseller");
$c->delete_reseller($resellername);
$d->fill_element('//*[@id="Resellers_table_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty'), 'Reseller was deleted');

done_testing;
# vim: filetype=perl
