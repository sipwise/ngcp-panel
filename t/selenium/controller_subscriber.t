use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

my ($port) = @_;
my $d = Selenium::Collection::Functions::create_driver($port);
my $c = Selenium::Collection::Common->new(
    driver => $d
);

my $customerid = ("id" . int(rand(100000)) . "ok");
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $emailstring = ("test" . int(rand(10000)) . "\@example.org");
my $username = ("demo" . int(rand(10000)) . "name");
my $bsetname = ("test" . int(10000) . "bset");
my $destinationname = ("test" . int(10000) . "dset");
my $sourcename = ("test" . int(10000) . "source");
my $setname = ("test" . int(rand(10000)) . "set");
my $profilename = ("test" . int(rand(10000)) . "profile");
my $contactmail = ("contact" . int(rand(100000)) . '@test.org');
my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $billingname = ("billing" . int(rand(100000)) . "test");
my $run_ok = 0;

$c->login_ok();
$c->create_domain($domainstring);
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_contact($contactmail, $resellername);
$c->create_billing_profile($billingname, $resellername);
$c->create_customer($customerid, $contactmail, $billingname);

diag("Open Customer details");
$d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty', 'css'), 'Garbage test not found');
$d->fill_element('#Customer_table_filter input', 'css', $customerid);
ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $customerid), 'Customer found');
$d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(),"Details")]', 'xpath', '//*[@id="Customer_table_filter"]//input');

diag("Try to add an empty Subscriber");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="customer_details"]//div//a[contains(text(), "Subscribers")]'));
$d->find_element('Create Subscriber', 'link_text')->click();
$d->unselect_if_selected('//*[@id="domainidtable"]/tbody/tr[1]/td[4]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Domain field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "SIP Username field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "SIP Password field is required")]'));

diag("Fill in values");
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

diag("Search Subscriber");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber successfully created',  'Correct Alert was shown');
if($d->find_element_by_xpath('//*[@id="masthead"]/div/div/div/h2')->get_text() eq "Customers"){ #workaround for misbehaving ngcp panel randomly throwing test out of customer details
    $d->fill_element('#Customer_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#Customer_table tr > td.dataTables_empty'), 'Garbage text was not found');
    $d->fill_element('#Customer_table_filter input', 'css', $customerid);
    ok($d->wait_for_text('//*[@id="Customer_table"]/tbody/tr[1]/td[2]', $customerid), 'Found customer');
    $d->move_and_click('//*[@id="Customer_table"]/tbody/tr[1]//td//div//a[contains(text(), "Details")]', 'xpath', '//*[@id="Customer_table_filter"]/label/input');
}
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->fill_element('//*[@id="subscribers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscribers_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscribers_table_filter"]/label/input', 'xpath', $username);
ok($d->wait_for_text('//*[@id="subscribers_table"]/tbody/tr/td[2]', $username), 'Subscriber was found');

diag("Go to 'Subscriber Profiles' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Subscriber Profiles", 'link_text')->click();

diag("Try to create a Subscriber Profile Set");
$d->find_element('Create Subscriber Profile Set', 'link_text')->click();
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), 'Reseller found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $setname);
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a description. It describes things');
$d->find_element('//*[@id="save"]')->click();

diag("Search Subscriber Profile Set");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber profile set successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);

diag("Check details");
ok($d->wait_for_text('//*[@id="subscriber_profile_sets_table"]/tbody/tr/td[3]', $setname), 'Name is correct');
ok($d->wait_for_text('//*[@id="subscriber_profile_sets_table"]/tbody/tr/td[4]', 'This is a description. It describes things'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr//td[contains(text(), "' . $resellername .'")]'), 'Reseller is correct');

diag("Enter 'Profiles' menu");
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Profiles")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');

diag("Try to create a Subscriber Profile");
$d->find_element('Create Subscriber Profile', 'link_text')->click();
$d->fill_element('//*[@id="name"]', 'xpath', $profilename);
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a description. It describes things');
$d->scroll_to_element($d->find_element('//*[@id="attribute.ncos"]'));
$d->select_if_unselected('//*[@id="attribute.ncos"]');
$d->find_element('//*[@id="save"]')->click();

diag("Search Subscriber Profile");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber profile successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_table_filter"]/label/input', 'xpath', $profilename);

diag("Check details");
ok($d->wait_for_text('//*[@id="subscriber_profile_table"]/tbody/tr/td[3]', $profilename), 'Name is correct');
ok($d->wait_for_text('//*[@id="subscriber_profile_table"]/tbody/tr/td[4]', 'This is a description. It describes things'), 'Description is correct');
ok($d->wait_for_text('//*[@id="subscriber_profile_table"]/tbody/tr/td[2]', $setname), 'Profile Set is correct');

diag("Go to 'Subscribers' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Subscribers", 'link_text')->click();

diag("Check Subscriber details");
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[3]', $contactmail), 'Contact Email is correct');
ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[4]', $username), 'Subscriber name is correct');
ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[5]', $domainstring), 'Domain name is correct');

diag("Go to 'Subscriber Details' page");
$d->move_and_click('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Details")]', 'xpath', '//*[@id="subscriber_table_filter"]//input');

diag("Edit master data");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="subscriber_data"]//div//a[contains(text(), "Master Data")]'));
$d->find_element('Edit', 'link_text')->click();

diag("Add Subscriber to profile");
$d->fill_element('//*[@id="profile_setidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#profile_setidtable tr > td.dataTables_empty'), 'Garbage Text was not found');
$d->fill_element('//*[@id="profile_setidtable_filter"]/label/input', 'xpath', $setname);
ok($d->wait_for_text('//*[@id="profile_setidtable"]/tbody/tr/td[3]', $setname), 'Subscriber Profile was found');
$d->select_if_unselected('//*[@id="profile_setidtable"]/tbody/tr/td[5]');
$d->find_element('//*[@id="save"]')->click();

diag("Check details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Successfully updated subscriber',  'Correct Alert was shown');
=pod
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Subscribers", 'link_text')->click();
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[3]', $contactmail), 'Subscriber was found');
$d->move_and_click('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Details")]', 'xpath', '//*[@id="subscriber_table_filter"]//input');
=cut
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="subscriber_data"]//div//a[contains(text(), "Master Data")]'));
ok($d->find_element_by_xpath('//*[@id="subscribers_table"]//tr/td[contains(text(), "Subscriber Profile Set")]/../td[contains(text(), "'. $setname .'")]'));
ok($d->find_element_by_xpath('//*[@id="subscribers_table"]//tr/td[contains(text(), "Subscriber Profile")]/../td[contains(text(), "'. $profilename .'")]'));

diag("Lock Subscriber");
$d->find_element("Edit", 'link_text')->click();
$d->find_element('//*[@id="lock"]/option[contains(text(), "global")]')->click();
$d->find_element('//*[@id="status"]/option[contains(text(), "locked")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Subscriber was locked");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Successfully updated subscriber',  'Correct Alert was shown');
if($d->find_element_by_xpath('//*[@id="masthead"]/div/div/div/h2')->get_text() eq "Subscribers"){ #workaround for misbehaving ngcp panel randomly throwing test out of customer details
    $d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
    $d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
    ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[4]', $username), 'Found Subscriber');
    $d->move_and_click('//*[@id="subscriber_table"]//tr[1]//td//a[contains(text(), "Details")]', 'xpath', '//*[@id="subscriber_table_filter"]/label/input');
}

diag("Unlock Subscriber");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="subscriber_data"]//div//a[contains(text(), "Master Data")]'));
ok($d->find_element_by_xpath('//*[@id="subscribers_table"]//tr//td[contains(text(), "Status")]/../td[contains(text(), "locked")]'), 'Status is correct');
$d->find_element("Edit", 'link_text')->click();
$d->find_element('//*[@id="lock"]')->click();
$d->find_element('//*[@id="lock"]/option[contains(text(), "none")]')->click();
$d->find_element('//*[@id="status"]')->click();
$d->find_element('//*[@id="status"]/option[contains(text(), "active")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if subscriber was unlocked");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Successfully updated subscriber',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="subscribers_table"]//tr//td[contains(text(), "Status")]/../td[contains(text(), "active")]'), 'Status is correct');

diag("Go to 'Subscriber Preferences' page");
$d->find_element("Preferences", 'link_text')->click();

diag("Try to change subscriber IVR Language");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "language")]'));
$d->move_and_click('//table//tr/td[contains(text(), "language")]/..//td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "conference_pin")]/..//td//a[contains(text(), "Edit")]');

diag("Change Language to German");
$d->find_element('//*[@id="language"]/option[contains(text(), "German")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Language has been applied");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Preference language successfully updated',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="preference_groups"]//div//a[contains(text(),"Internals")]'));
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "language")]/../td/select/option[contains(text(), "German") and @selected="selected"]'), '"German" has been selected');

diag("Try to enable Call Recording");
$d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "record_call")]'));
$d->move_and_click('//table//tr/td[contains(text(), "record_call")]/..//td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "nat_sipping")]/..//td//a[contains(text(), "Edit")]');

diag("Enable Call Recording");
$d->select_if_unselected('//*[@id="record_call"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check if Call Recording was enabled");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Preference record_call successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "record_call")]/../td//input[@checked="checked"]'), 'Call recording was enabled');

diag("Try to add a Call Forward");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('Call Forwards', 'link_text'));
$d->move_and_click('//*[@id="preferences_table_cf"]/tbody/tr/td[contains(text(), "Unconditional")]/../td/div/a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Forwards")]');
$d->fill_element('//*[@id="destination.uri.destination"]', 'xpath', '43123456789');
$d->find_element('//*[@id="cf_actions.advanced"]')->click();

diag("Add a new Source Set");
$d->find_element('//*[@id="cf_actions.edit_source_sets"]')->click();
$d->find_element('Create New', 'link_text')->click();
$d->fill_element('//*[@id="name"]', 'xpath', $sourcename);
$d->fill_element('//*[@id="source.0.source"]', 'xpath', '43*');

diag("Add another source");
$d->find_element('//*[@id="source_add"]')->click();
$d->fill_element('//*[@id="source.1.source"]', 'xpath', '494331337');
$d->find_element('//*[@id="save"]')->click();

diag("Check Source Set details");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $sourcename . '")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $sourcename . '")]/../td[contains(text(), "whitelist")]'), 'Mode is correct');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $sourcename . '")]/../td[contains(text(), "43*")]'), 'Number 1 is correct');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $sourcename . '")]/../td[text()[contains(., "494331337")]]'),'Number 2 is correct');
$d->find_element('//*[@id="mod_close"]')->click();

diag("Add a new B-Number Set");
$d->find_element('//*[@id="cf_actions.edit_bnumber_sets"]')->click();
$d->find_element('Create New', 'link_text')->click();
$d->fill_element('//*[@id="name"]', 'xpath', $bsetname);
$d->fill_element('//*[@id="bnumbers.0.number"]', 'xpath', '1234567890');
$d->find_element('//*[@id="save"]')->click();

diag("Check B-Number Set details");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $bsetname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $bsetname . '")]/../td[contains(text(), "1234567890")]'), 'Number is correct');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $bsetname . '")]/../td[contains(text(), "whitelist")]'), 'Mode is correct');
$d->find_element('//*[@id="mod_close"]')->click();

diag("Add a new Destination Set");
$d->find_element('//*[@id="cf_actions.edit_destination_sets"]')->click();
$d->find_element('Create New', 'link_text')->click();
$d->fill_element('//*[@id="name"]', 'xpath', $destinationname);
$d->fill_element('//*[@id="destination.0.uri.destination"]', 'xpath', '1234567890');
$d->find_element('//*[@id="save"]')->click();

diag("Check Destination Set details");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $destinationname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//table//tr/td[contains(text(), "' . $destinationname . '")]/../td[contains(text(), "1234567890")]'), 'Number is correct');
$d->find_element('//*[@id="mod_close"]')->click();

diag("Use new Sets");
$d->find_element('//*[@id="callforward_controls_add"]')->click();
$d->find_element('//*[@id="active_callforward.0.source_set"]/option[contains(text(), "' . $sourcename . '")]')->click();
ok($d->find_element_by_xpath('//select//option[contains(text(), "' . $sourcename . '")]')->click(), 'Source set has been found');
ok($d->find_element_by_xpath('//select//option[contains(text(), "' . $destinationname . '")]')->click(), 'Destination Set has been found');
ok($d->find_element_by_xpath('//select//option[contains(text(), "' . $bsetname . '")]')->click(), 'B-Set has been found');

diag("Save");
$d->find_element('//*[@id="cf_actions.save"]')->click();

diag("Check if call-forward has been applied");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Successfully saved Call Forward',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="preferences_table_cf"]/tbody/tr[1]/td[contains(text(), ' . $bsetname . ')]'), 'B-Set was selected');
ok($d->find_element_by_xpath('//*[@id="preferences_table_cf"]/tbody/tr[1]/td[contains(text(), ' . $destinationname . ')]'), 'Destination set was selected');

diag("Try to add Call Blockings");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('Call Blockings', 'link_text'));

diag("Edit 'block_in_mode'");
$d->move_and_click('//table//tr/td[contains(text(), "block_in_mode")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
$d->find_element('//*[@id="block_in_mode"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check details");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('Call Blockings', 'link_text'));
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Preference block_in_mode successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_mode")]/../td/input[@checked="checked"]'), 'Setting is correct');

diag("Edit 'block_in_list'");
$d->move_and_click('//table//tr/td[contains(text(), "block_in_list")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
$d->fill_element('//*[@id="block_in_list"]', 'xpath', '1337');
$d->find_element('//*[@id="add"]')->click();
$d->fill_element('//*[@id="block_in_list"]', 'xpath', '42');
$d->find_element('//*[@id="add"]')->click();
$d->find_element('//*[@id="mod_close"]')->click();

diag("Check details");
$d->find_element('//*[@id="toggle-accordions"]')->click();
#is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Preference block_in_list successfully created',  'Correct Alert was shown');
$d->scroll_to_element($d->find_element('Call Blockings', 'link_text'));
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_list")]/../td[contains(text(), "1337")]'), 'Number 1 is correct');
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_list")]/../td[text()[contains(., "42")]]'), 'Number 2 is correct');

diag("Disable Entry");
$d->move_and_click('//table//tr/td[contains(text(), "block_in_list")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
$d->find_element('//*[@id="mod_edit"]//div//input[@value="1337"]/../a[2]')->click();
$d->find_element('//*[@id="mod_close"]')->click();

diag("Check if Entry has been disabled");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('Call Blockings', 'link_text'));
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_list")]/../td/span[@class="ngcp-entry-disabled"]/../span[contains(text(), "1337")]'), 'Entry has been disabled');

diag("Edit 'block_in_clir'");
$d->move_and_click('//table//tr/td[contains(text(), "block_in_clir")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
$d->find_element('//*[@id="block_in_clir"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if value was set");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Preference block_in_clir successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "block_in_clir")]/../td/input[@checked="checked"]'), 'Setting is correct');

diag("Go to 'Subscribers' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Subscribers', 'link_text')->click();

diag("Try to NOT delete Subscriber");
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[4]', $username), 'Subscriber was found');
$d->move_and_click('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Terminate")]', 'xpath', '//*[@id="subscriber_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Subscriber is still here");
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->wait_for_text('//*[@id="subscriber_table"]/tbody/tr/td[4]', $username), 'Subscriber is still here');

diag("Try to delete Subscriber");
$d->move_and_click('//*[@id="subscriber_table"]/tbody/tr[1]/td/div/a[contains(text(), "Terminate")]', 'xpath', '//*[@id="subscriber_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Subscriber has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Successfully terminated subscriber',  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_table_filter"]/label/input', 'xpath', $username);
ok($d->find_element_by_css('#subscriber_table tr > td.dataTables_empty'), 'Subscriber has been deleted');
$d->find_element('//*[@id="content"]//div//a[contains(text(), "Back")]')->click();

diag("Go to 'Subscriber Profiles' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Subscriber Profiles', 'link_text')->click();

diag("Try to NOT Delete Subscriber Profile Set");
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);
ok($d->wait_for_text('//*[@id="subscriber_profile_sets_table"]/tbody/tr/td[3]', $setname), 'Profile Set was found');
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Subscriber Profile Set is still here");
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);
ok($d->wait_for_text('//*[@id="subscriber_profile_sets_table"]/tbody/tr/td[3]', $setname), 'Subscriber Profile Set is still here');

diag("Try to delete Subscriber Profile Set");
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Subscriber Profile Set has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber profile set successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Subscriber Profile Set has been deleted');

$c->delete_customer($customerid);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);
$c->delete_contact($contactmail);
$c->delete_billing_profile($billingname);
$c->delete_domain($domainstring);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_subscriber.png");
    }
    $d->quit();
    done_testing;
}