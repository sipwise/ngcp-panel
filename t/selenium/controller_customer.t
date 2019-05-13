use strict;
use warnings;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
);

$d->login_ok();

my @chars = ("A".."Z", "a".."z");
my $rnd_id;
$rnd_id .= $chars[rand @chars] for 1..8;

diag("Go to Customers page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Customers", 'link_text')->click();

diag("Create a Customer");
$d->find_element('//*[@id="masthead"]//h2[contains(text(),"Customers")]');
$d->find_element('Create Customer', 'link_text')->click();
diag(" - fill contact data");
$d->fill_element('#contactidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#contactidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#contactidtable_filter input', 'css', 'default-customer');
$d->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]/td[contains(text(),"default-customer")]/..//input[@type="checkbox"]');
diag(" - fill billing data");
$d->fill_element('#billing_profileidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#billing_profileidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#billing_profileidtable_filter input', 'css', 'Default Billing Profile');
$d->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]/td[contains(text(),"Default Billing Profile")]/..//input[@type="checkbox"]');
diag(" - fill product data");
eval { #lets only try this
    $d->select_if_unselected('//table[@id="productidtable"]/tbody/tr[1]/td[contains(text(),"Basic SIP Account")]/..//input[@type="checkbox"]');
};
diag(" - fill external_id");
$d->scroll_to_id('external_id');
$d->fill_element('#external_id', 'css', $rnd_id);
diag(" - save");
$d->find_element('#save', 'css')->click();

diag("Open Details for our just created Customer");
sleep 2; #Else we might search on the previous page
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#Customer_table tr > td.dataTables_empty', 'css');
$d->fill_element('#Customer_table_filter input', 'css', $rnd_id);
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $rnd_id), 'Customer found');
$d->move_action(element=> $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]'));
$d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]')->click();

diag("Edit our contact");
$d->find_element('//div[contains(@class,"accordion-heading")]//a[contains(text(),"Contact Details")]')->click();
$d->find_element('//div[contains(@class,"accordion-body")]//*[contains(@class,"btn-primary") and contains(text(),"Edit Contact")]')->click();
$d->fill_element('div.modal #firstname', 'css', "Alice");
$d->fill_element('#company', 'css', 'Sipwise');
# Choosing Country:
$d->fill_element('#countryidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#countryidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#countryidtable_filter input', 'css', 'Ukraine');
$d->select_if_unselected('//table[@id="countryidtable"]/tbody/tr[1]/td[contains(text(),"Ukraine")]/..//input[@type="checkbox"]');
# Save
$d->find_element('#save', 'css')->click();

diag("Check if successful");
$d->find_element('//div[contains(@class,"accordion-body")]//table//td[contains(text(),"Sipwise")]');

diag("Edit Fraud Limits");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Fraud Limits")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(),"Fraud Limits")]'));
$d->move_and_click('//*[@id="collapse_fraud"]//table//tr//td[text()[contains(.,"Monthly Settings")]]/../td//a[text()[contains(.,"Edit")]]', 'xpath');
$d->fill_element('#fraud_interval_limit', 'css', "100");
$d->fill_element('#fraud_interval_notify', 'css', 'mymail@example.org');
$d->find_element('#save', 'css')->click();

diag("Check Fraud Limit details");
ok($d->find_element_by_xpath('//*[@id="collapse_fraud"]//table//tr//td[contains(text(), "Monthly Settings")]/../td[contains(text(), "100")]'), "Limit is correct");
ok($d->wait_for_text('//*[@id="collapse_fraud"]//table//tr//td[contains(text(), "Monthly Settings")]/../td[4]', 'mymail@example.org'), "Mail is correct");

diag("Terminate our customer");
$d->find_element('//a[contains(@class,"btn-primary") and text()[contains(.,"Back")]]')->click();
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#Customer_table tr > td.dataTables_empty', 'css');
$d->fill_element('#Customer_table_filter input', 'css', $rnd_id);
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $rnd_id), 'Found customer');
$d->move_action(element => $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]'));
$d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();
$d->find_text("Customer successfully terminated");

done_testing;
# vim: filetype=perl
