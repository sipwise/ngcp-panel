use strict;
use warnings;

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

my $pbx = $ENV{PBX};

if(!$pbx){
    print "---PBX check is DISABLED---\n";
    $pbx = 0;
} else {
    print "---PBX check is ENABLED---\n";
};
$d->login_ok();

my $domainstring = ("test" . int(rand(10000)) . ".example.org"); #create string for checking later
$c->create_domain($domainstring);

my @chars = ("A".."Z", "a".."z");
my $rnd_id;
$rnd_id .= $chars[rand @chars] for 1..8;

diag("Go to Customers page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Customers", 'link_text')->click();

diag("Create a Customer");
$d->find_element('//*[@id="masthead"]//h2[contains(text(),"Customers")]');
$d->find_element('Create Customer', 'link_text')->click();

diag("Fill contact data");
$d->fill_element('#contactidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#contactidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#contactidtable_filter input', 'css', 'default-customer');
$d->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]/td[contains(text(),"default-customer")]/..//input[@type="checkbox"]');

diag("Fill billing data");
$d->fill_element('#billing_profileidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#billing_profileidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#billing_profileidtable_filter input', 'css', 'Default Billing Profile');
$d->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]/td[contains(text(),"Default Billing Profile")]/..//input[@type="checkbox"]');

diag("Fill product data");
if($pbx == 1){
    $d->select_if_unselected('//table[@id="productidtable"]/tbody/tr[1]/td[contains(text(),"Basic SIP Account")]/..//input[@type="checkbox"]');
};
diag("Fill external_id");
$d->scroll_to_id('external_id');
$d->fill_element('#external_id', 'css', $rnd_id);

diag("Save");
$d->find_element('#save', 'css')->click();

diag("Open Details for our just created Customer");
sleep 2; #Else we might search on the previous page
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $rnd_id);
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $rnd_id), 'Customer found');
$d->move_action(element=> $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]'));
$d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]')->click();

diag("Edit our contact");
$d->find_element('//div[contains(@class,"accordion-heading")]//a[contains(text(),"Contact Details")]')->click();
$d->find_element('//div[contains(@class,"accordion-body")]//*[contains(@class,"btn-primary") and contains(text(),"Edit Contact")]')->click();
$d->fill_element('div.modal #firstname', 'css', "Alice");
$d->fill_element('#company', 'css', 'Sipwise');
ok($d, 'Inserting name works');
# Choosing Country:
$d->fill_element('#countryidtable_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#countryidtable tr > td.dataTables_empty', 'css');
$d->fill_element('#countryidtable_filter input', 'css', 'Ukraine');
$d->select_if_unselected('//table[@id="countryidtable"]/tbody/tr[1]/td[contains(text(),"Ukraine")]/..//input[@type="checkbox"]');
ok($d, 'Successfuly added a Country');
$d->find_element('#save', 'css')->click(); # Save

diag("Check if successful");
$d->find_element('//div[contains(@class,"accordion-body")]//table//td[contains(text(),"Sipwise")]');

diag("Trying to add a subscriber");
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
my $emailstring = ("test" . int(rand(10000)) . "\@example.org");
$d->find_element('//*[@id="email"]')->send_keys($emailstring);
my $username = ('demo' . int(rand(1000)));
$d->find_element('//*[@id="webusername"]')->send_keys($username);
$d->find_element('//*[@id="webpassword"]')->send_keys('testing1234'); #workaround for misclicking on ok button
$d->find_element('//*[@id="gen_password"]')->click();
$d->find_element('//*[@id="username"]')->send_keys($username);
$d->find_element('//*[@id="password"]')->send_keys('testing1234'); #using normal pwd, cant easily seperate both generate buttons
$d->find_element('//*[@id="save"]')->click();

diag("Trying to find subscriber");
$d->find_element('//*[@id="subscribers_table_filter"]/label/input')->send_keys($username);
ok($d->wait_for_text('//*[@id="subscribers_table"]/tbody/tr/td[2]', $username), 'Subscriber was found');

diag("Edit Fraud Limits");
$d->find_element('//div[contains(@class,"accordion-heading")]//a[contains(text(),"Fraud Limits")]')->click();
$d->scroll_to_element($d->find_element('//div[contains(@class,"accordion-heading")]//a[contains(text(),"Fraud Limits")]'));
$d->move_and_click('//*[@id="collapse_fraud"]//table//tr//td[text()[contains(.,"Monthly Settings")]]/../td//a[text()[contains(.,"Edit")]]', 'xpath');

diag("Do Edit Fraud Limits");
$d->fill_element('#fraud_interval_limit', 'css', "100");
$d->fill_element('#fraud_interval_notify', 'css', 'mymail@example.org');
$d->find_element('#save', 'css')->click();
$d->find_element('//div[contains(@class,"accordion-body")]//table//td[contains(text(),"mymail@example.org")]');

diag("Create a new Phonebook entry");
$d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
$d->find_element("Create Phonebook Entry", 'link_text')->click();
$d->fill_element('//*[@id="name"]', 'xpath', 'Test Name');
$d->fill_element('//*[@id="number"]', 'xpath', '0123456789');
$d->find_element('//*[@id="save"]')->click();

diag("Check if Phonebook Entry has been created");
$d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Phonebook")]')->click();
$d->scroll_to_element($d->find_element("Create Phonebook Entry", 'link_text'));
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#phonebook_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="phonebook_table_filter"]/label/input', 'xpath', '0123456789');
ok($d->wait_for_text('//*[@id="phonebook_table"]/tbody/tr/td[3]', '0123456789'), 'Entry has been found');

diag("Create a new Location");
$d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Locations")]')->click();
$d->find_element("Create Location", 'link_text')->click();

diag('Enter necessary information');
$d->fill_element('//*[@id="name"]', 'xpath', 'Test Location');
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a Test Location');
$d->fill_element('//*[@id="name"]', 'xpath', 'Test Location');
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '127.0.0.1');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="save"]')->click();

diag("Check if Location has been created");
$d->find_element('//*[@id="customer_details"]//div//div//a[contains(text(),"Locations")]')->click();
$d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#locations_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="locations_table_filter"]/label/input', 'xpath', 'Test Location');
ok($d->wait_for_text('//*[@id="locations_table"]/tbody/tr/td[2]', 'Test Location'), "Location has been found");

diag("Terminate our customer");
$d->find_element('//a[contains(@class,"btn-primary") and text()[contains(.,"Back")]]')->click();
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('#Customer_table_filter input', 'css', $rnd_id);
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $rnd_id), 'Found customer');
$d->move_action(element => $d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]'));
$d->find_element('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Terminate")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();
ok($d->find_text("Customer successfully terminated"), 'Text "Customer successfully terminated" appears');

$c->delete_domain($domainstring);
done_testing;
# vim: filetype=perl
