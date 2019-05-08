use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
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

my $customerid = ("id" . int(rand(100000)) . "ok");
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $emailstring = ("test" . int(rand(10000)) . "\@example.org");
my $username = ("demo" . int(rand(10000)) . "name");
my $bsetname = ("test" . int(10000) . "bset");
my $destinationname = ("test" . int(10000) . "dset");

$c->login_ok();
$c->create_domain($domainstring);
$c->create_customer($customerid);

diag("Open Details for our just created Customer");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $customerid), 'Customer found');
$d->move_action(element=> $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]'));
$d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]')->click();

diag("Trying to add a Subscriber");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Subscribers")]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Subscribers")]'));
$d->find_element('Create Subscriber', 'link_text')->click();

diag('Enter necessary information');
$d->fill_element('//*[@id="domainidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#domainidtable tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="domainidtable_filter"]/label/input', 'xpath', $domainstring);
ok($d->wait_for_text('//*[@id="domainidtable"]/tbody/tr[1]/td[3]', $domainstring), 'Domain found');
$d->select_if_unselected('//*[@id="domainidtable"]/tbody/tr[1]/td[4]/input');
$d->find_element('//*[@id="e164.cc"]')->send_keys('43');
$d->find_element('//*[@id="e164.ac"]')->send_keys('99');
$d->find_element('//*[@id="e164.sn"]')->send_keys(int(rand(99999999)));
$d->find_element('//*[@id="email"]')->send_keys($emailstring);
$d->find_element('//*[@id="webusername"]')->send_keys($username);
$d->find_element('//*[@id="webpassword"]')->send_keys('testing1234'); #workaround for misclicking on ok button
$d->find_element('//*[@id="gen_password"]')->click();
$d->find_element('//*[@id="username"]')->send_keys($username);
$d->find_element('//*[@id="password"]')->send_keys('testing1234'); #using normal pwd, cant easily seperate both generate buttons
$d->find_element('//*[@id="save"]')->click();

diag('Trying to find Subscriber');
$d->fill_element('//*[@id="subscribers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscribers_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscribers_table_filter"]/label/input', 'xpath', $username);
ok($d->wait_for_text('//*[@id="subscribers_table"]/tbody/tr/td[2]', $username), 'Subscriber was found');

diag('Go to Subscribers page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Subscribers", 'link_text')->click();

diag('Find Subscriber here');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[4]', $username), 'Subscriber was found');

diag('Go to Subscriber details');
$d->move_action(element => $d->find_element('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Details")]'));
$d->find_element('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Details")]')->click();

diag('Go to Subscriber preferences');
$d->find_element("Preferences", 'link_text')->click();

diag('Trying to add a simple call forward');
$d->find_element("Call Forwards", 'link_text')->click();
$d->move_action(element => $d->find_element('//*[@id="preferences_table_cf"]/tbody/tr/td[contains(text(), "Unconditional")]/../td/div/a[contains(text(), "Edit")]'));
$d->find_element('//*[@id="preferences_table_cf"]/tbody/tr/td[contains(text(), "Unconditional")]/../td/div/a[contains(text(), "Edit")]')->click();
$d->fill_element('//*[@id="destination.uri.destination"]', 'xpath', '43123456789');
$d->find_element('//*[@id="cf_actions.advanced"]')->click();

diag('Add a new B-Number set');
$d->find_element('//*[@id="cf_actions.edit_bnumber_sets"]')->click();
$d->find_element('Create New', 'link_text')->click();
$d->fill_element('//*[@id="name"]', 'xpath', $bsetname);
$d->fill_element('//*[@id="bnumbers.0.number"]', 'xpath', '1234567890');
$d->find_element('//*[@id="save"]')->click();
$d->find_element('//*[@id="mod_close"]')->click();

diag('Add a new Destination set');
$d->find_element('//*[@id="cf_actions.edit_destination_sets"]')->click(); 
$d->find_element('Create New', 'link_text')->click();
$d->fill_element('//*[@id="name"]', 'xpath', $destinationname);
$d->fill_element('//*[@id="destination.0.uri.destination"]', 'xpath', '1234567890');
$d->find_element('//*[@id="save"]')->click();
$d->find_element('//*[@id="mod_close"]')->click();
$d->find_element('//*[@id="callforward_controls_add"]')->click();

diag('Use new Sets');
$d->find_element('//select//option[contains(text(), "' . $bsetname . '")]')->click();
$d->find_element('//select//option[contains(text(), "' . $destinationname . '")]')->click();
$d->find_element('//*[@id="cf_actions.save"]')->click();

diag('Check if call-forward has been applied');
ok($d->find_element_by_xpath('//*[@id="preferences_table_cf"]/tbody/tr[1]/td[contains(text(), ' . $bsetname . ')]'), 'B-Set was found');
ok($d->find_element_by_xpath('//*[@id="preferences_table_cf"]/tbody/tr[1]/td[contains(text(), ' . $destinationname . ')]'), 'Destination set was found');

diag('Go to Subscribers Page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Subscribers", 'link_text')->click();

diag('Trying to delete Subscriber');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[4]', $username), 'Subscriber was found');
$d->move_action(element => $d->find_element('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Terminate")]'));
$d->find_element('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Terminate")]')->click();
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Subscriber has been deleted');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');

$c->delete_customer($customerid);
$c->delete_domain($domainstring);


done_testing();