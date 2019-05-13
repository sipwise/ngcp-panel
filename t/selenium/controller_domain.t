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
ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[3]', $domainstring), 'Entry was found');

diag("Open Preferences of first Domain");
$d->move_and_click('//*[@id="Domain_table"]//tr[1]//td//a[contains(text(), "Preferences")]', 'xpath');

diag('Open the tab "Access Restrictions"');
like($d->get_path, qr!domain/\d+/preferences!);
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

done_testing();
