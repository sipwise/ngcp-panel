use warnings;
use strict;
use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag like)];
use Selenium::Remote::Driver::FirefoxExtensions;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
);

diag('Logging in');
$d->login_ok();

diag('Go to domains page');
$d->find_element('//*[@id="main-nav"]/li[5]/a')->click();
$d->find_element('//*[@id="main-nav"]/li[5]/ul/li[6]/a')->click();

diag('Try to add a domain');
$d->find_element('//*[@id="content"]/div/div[1]/span[2]/a')->click();
ok(1, "Domain website seems to exist");
$d->find_element('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input')->click(); #select default reseller
my $domainstring = ("test" . int(rand(10000)) . ".example.org"); #create string for checking later
$d->find_element('//*[@id="domain"]')->send_keys($domainstring);
$d->find_element('//*[@id="save"]')->click();
ok(2, "Create field shows and works");

diag("Check if entry exists and if the search works");
$d->find_element('//*[@id="Domain_table_filter"]/label/input')->clear();
$d->find_element('//*[@id="Domain_table_filter"]/label/input')->send_keys($domainstring); #actual value
sleep(1) until $d->find_element('//*[@id="Domain_table"]/tbody/tr/td[3]')->get_text() ~~ $domainstring; #waiting because ajax
my $domainfromtable = $d->get_text('//*[@id="Domain_table"]/tbody/tr/td[3]');
is($domainfromtable, $domainstring, "Entry was found");
sleep 1; # prevent stale element exception

diag("Open Preferences of first Domain");
my ($row, $edit_link);
$row = $d->find_element('//table[@id="Domain_table"]/tbody/tr[1]');
$edit_link = $d->find_element('(//table[@id="Domain_table"]/tbody/tr[1]/td//a)[contains(text(),"Preferences")]');
ok($edit_link);
$d->move_action(element => $row);
$edit_link->click();

diag('Open the tab "Access Restrictions"');
like($d->get_path, qr!domain/\d+/preferences!);
$d->find_element("Access Restrictions", 'link_text')->click();

diag("Click edit for the preference concurrent_max");
sleep 1;
$row = $d->find_element('//table/tbody/tr/td[normalize-space(text()) = "concurrent_max"]');
ok($row);
$edit_link = $d->find_child_element($row, '(./../td//a)[2]');
ok($edit_link);
$d->move_action(element => $row);
$edit_link->click();

diag("Try to change this to a value which is not a number");
my $formfield = $d->find_element('#concurrent_max', 'css');
ok($formfield);
$formfield->clear();
$formfield->send_keys('thisisnonumber');
$d->find_element("#save", 'css')->click();

diag('Type 789 and click Save');
$d->find_text('Value must be an integer');
$formfield = $d->find_element('#concurrent_max', 'css');
ok($formfield);
$formfield->clear();
$formfield->send_keys('789');
$d->find_element('#save', 'css')->click();
done_testing();
