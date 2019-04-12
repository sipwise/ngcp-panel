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

diag('Logging in');
$d->login_ok();

my $domainstring = ("test" . int(rand(10000)) . ".example.org"); #create string for checking later
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

diag('Deleting Domain');
$c->delete_domain($domainstring);

diag('Check if Domain still exists');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Domain was deleted');

done_testing();
