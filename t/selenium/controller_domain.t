use warnings;
use strict;
use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag like)];
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

my $domainstring = ("domain" . int(rand(100000)) . ".example.org");

$c->login_ok();
$c->create_domain($domainstring);

diag("Check if entry exists and if the search works");
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr/td[3]', $domainstring), 'Entry was found');

diag("Open Preferences of first Domain");
my ($row, $edit_link);
$row = $d->find_element('//table[@id="Domain_table"]/tbody/tr[1]');
$edit_link = $d->find_element('(//table[@id="Domain_table"]/tbody/tr[1]/td//a)[contains(text(),"Preferences")]');
ok($edit_link, 'Edit Link is here');
$d->move_action(element => $row);
$edit_link->click();

diag('Open the tab "Access Restrictions"');
like($d->get_path, qr!domain/\d+/preferences!);
$d->find_element("Access Restrictions", 'link_text')->click();

diag("Click edit for the preference concurrent_max");
$row = $d->find_element('//table/tbody/tr/td[normalize-space(text()) = "concurrent_max"]');
ok($row, 'concurrent_max found');
$edit_link = $d->find_child_element($row, '(./../td//a)[2]');
ok($edit_link, 'Found edit button');
$d->move_action(element => $row);
$edit_link->click();

diag("Try to change this to a value which is not a number");
my $formfield = $d->find_element('#concurrent_max', 'css');
ok($formfield, 'Input field found');
$formfield->clear();
$formfield->send_keys('thisisnonumber');
$d->find_element("#save", 'css')->click();

diag('Type 789 and click Save');
ok($d->find_text('Value must be an integer'), 'Wrong value detected');
$formfield = $d->find_element('#concurrent_max', 'css');
ok($formfield, 'Input field found');
$formfield->clear();

diag('Saving integer value into "concurrent_max"');
$formfield->send_keys('789');
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

done_testing();
