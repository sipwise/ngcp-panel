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
$d->move_action(element=> $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]/td[3]'));
$d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]/td[5]/div/a[1]')->click();
$d->find_element('#mod_close', 'css')->click();

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
