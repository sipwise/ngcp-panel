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

my $billingname = ("billing" . int(rand(100000)) . "test");
my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $billingnetwork = ("billing" . int(rand(100000)) . "network");
my $zonename = ("billing" . int(rand(100000)) . "zone");
my $zonedetailname = ("zone" . int(rand(100000)) . "detail");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_billing_profile($billingname, $resellername);

diag("Go to 'Billing Profiles' page");
$d->find_element('//*[@class="brand"]')->click();
$d->find_element('//*[@id="content"]//div[contains(text(), "Billing")]/../../div/a')->click();

diag("Try to create an empty Billing Profile");
$d->find_element('Create Billing Profile', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Handle field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Create a legit Billing Profile");
$d->find_element('//*[@id="mod_close"]')->click();

diag("Search Billing Profile");
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);

diag("Check if values are correct");
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]/tbody/tr/td[2][contains(text(), "' . $billingname . '")]'), 'Billing name is correct');
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]/tbody/tr/td[3][contains(text(), "' . $resellername . '")]'), 'Reseller name is correct');

diag("Edit Billing Profile");
$d->move_and_click('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Edit")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');
$billingname = ("billing" . int(rand(100000)) . "test");
$d->fill_element('#name', 'css', $billingname);
$d->select_if_unselected('//*[@id="prepaid"]');
$d->fill_element('#interval_charge', 'css', '3.2');
$d->find_element('#save', 'css')->click();

diag("Check if values are correct");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing profile successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing name is correct');
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller name is correct');
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]//td/input[@checked="checked"]'), 'Prepaid setting is correct');

diag("Open 'Fees' page");
$d->move_and_click('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Fees")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');

diag("Go to 'Billing Zones' page");
$d->find_element('Edit Zones', 'link_text')->click();

diag("Create a Billing Zone");
$d->find_element('Create', 'link_text')->click();

diag("Save without entering anything");
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Zone field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="zone"]', 'xpath', $zonename);
$d->fill_element('//*[@id="detail"]', 'xpath', $zonedetailname);
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing Zone successfully created',  'Correct Alert was shown');

diag("Check Billing Zone details");
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', $zonename);
ok($d->find_element_by_xpath('//*[@id="billing_zone_table"]//tr[1]/td[contains(text(), "' . $zonename .'")]'), 'Billing Zone name is correct');
ok($d->find_element_by_xpath('//*[@id="billing_zone_table"]//tr[1]/td[contains(text(), "' . $zonedetailname . '")]'), 'Billing Zone detail is correct');

diag("Go back to Billing Fees page");
$d->find_element('Back', 'link_text')->click();

diag("Create a Billing Fee");
$d->find_element('Create Fee Entry', 'link_text')->click();

diag("Save without entering anything");
$d->unselect_if_selected('//*[@id="billing_zoneidtable"]//tr[1]/td[4]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Zone field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Destination field is required")]'));

diag("Fill in invalid values");
$d->fill_element('#source', 'css', '.*');
$d->fill_element('#destination', 'css', '.+');
$d->fill_element('//*[@id="onpeak_init_rate"]', 'xpath', 'e');
$d->fill_element('//*[@id="onpeak_init_interval"]', 'xpath', 'e');
$d->fill_element('//*[@id="onpeak_follow_rate"]', 'xpath', 'e');
$d->fill_element('//*[@id="onpeak_follow_interval"]', 'xpath', 'e');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Must be a number. May contain numbers, +, - and decimal separator")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Onpeak init interval must be greater than 0")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Onpeak follow interval must be greater than 0")]'));

diag("Fill in more invalid values");
$d->fill_element('//*[@id="onpeak_init_rate"]', 'xpath', '0');
$d->fill_element('//*[@id="onpeak_init_interval"]', 'xpath', '-10');
$d->fill_element('//*[@id="onpeak_follow_rate"]', 'xpath', '0');
$d->fill_element('//*[@id="onpeak_follow_interval"]', 'xpath', '-10');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Onpeak init interval must be greater than 0")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Onpeak follow interval must be greater than 0")]'));

diag("Fill in valid values");
$d->select_if_unselected('//*[@id="billing_zoneidtable"]//tr[1]/td[4]/input');
$d->fill_element('//*[@id="onpeak_init_interval"]', 'xpath', '1');
$d->fill_element('//*[@id="onpeak_follow_interval"]', 'xpath', '1');
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing Fee successfully created!',  'Correct Alert was shown');

diag("Check Billing Fee details");
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', $zonedetailname);
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), ".*")]'), 'Source pattern is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), ".+")]'), 'Destination pattern is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "Regular expression - longest pattern")]'), 'Match Mode is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "out")]'), 'Direction is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "' . $zonedetailname . '")]'), 'Zone detail is correct');

diag("Edit Billing Fee");
$d->move_and_click('//*[@id="billing_fee_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="billing_fee_table_filter"]/label/input');
$d->move_and_click('//*[@id="direction"]', 'xpath', '//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Billing Fee")]');
$d->find_element('//*[@id="direction"]/option[@value="in"]')->click();
$d->find_element('//*[@id="save"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing fee successfully changed!',  'Correct Alert was shown');

diag("Check Billing Fee details");
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), ".*")]'), 'Source pattern is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), ".+")]'), 'Destination pattern is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "Regular expression - longest pattern")]'), 'Match Mode is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "in")]'), 'Direction is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "' . $zonedetailname . '")]'), 'Zone detail is correct');

diag("Go back to Billing Profiles page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Billing', 'link_text')->click();

diag("Clone Billing Profile");
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile was found');
$d->move_and_click('//*[@id="billing_profile_table"]//tr[1]//td//a[contains(text(), "Duplicate")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');

diag("Fill in clone details");
my $clonename = ("billing" . int(rand(100000)) . "test");
$d->fill_element('//*[@id="handle"]', 'xpath', $clonename);
$d->fill_element('//*[@id="name"]', 'xpath', $clonename);
$d->find_element('//*[@id="save"]')->click();

diag("Search cloned Billing Profile");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing profile successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $clonename);
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $clonename . '")]'), 'Billing Profile was found');
$d->move_and_click('//*[@id="billing_profile_table"]//tr[1]//td//a[contains(text(), "Fees")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');

diag("Check if Fees got cloned properly");
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), ".*")]'), 'Source pattern is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), ".+")]'), 'Destination pattern is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "Regular expression - longest pattern")]'), 'Match Mode is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "in")]'), 'Direction is correct');
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "' . $zonedetailname . '")]'), 'Zone detail is correct');

diag("Check if Billing Zones got cloned properly");
$d->find_element('Edit Zones', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="billing_zone_table"]//tr[1]/td[contains(text(), "' . $zonename . '")]'), 'Billing Zone name is correct');
ok($d->find_element_by_xpath('//*[@id="billing_zone_table"]//tr[1]/td[contains(text(), "' . $zonedetailname . '")]'), 'Billing Zone detail is correct');

diag("Delete cloned Billing Profile");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Billing', 'link_text')->click();
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $clonename);
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $clonename . '")]'), 'Billing Profile was found');
$d->move_and_click('//*[@id="billing_profile_table"]//tr[1]//td//a[contains(text(), "Terminate")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if clone profile has been deleted");
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $clonename);
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Cloned Billing Profile has been deleted');

diag("Go back to Billing Fees");
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile was found');
$d->move_and_click('//*[@id="billing_profile_table"]/tbody/tr[1]//td//a[contains(text(), "Fees")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');

diag("Try to NOT delete Billing Fee");
$d->move_and_click('//*[@id="billing_fee_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="billing_fee_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Billing Fee is still here");
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', $zonedetailname);
ok($d->find_element_by_xpath('//*[@id="billing_fee_table"]//tr[1]/td[contains(text(), "' . $zonedetailname . '")]'), 'Billing Fee entry is still here');

diag("Try to delete Billing Fee");
$d->move_and_click('//*[@id="billing_fee_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="billing_fee_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing fee successfully deleted!',  'Correct Alert was shown');

diag("Check if Billing Fee has been deleted");
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', $zonedetailname);
ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Billing Fee entry has been deleted');

diag("Go To Billing Zones");
$d->find_element('Edit Zones', 'link_text')->click();

diag("Try to NOT delete Billing Zone");
$d->move_and_click('//*[@id="billing_zone_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="billing_zone_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Billing Zone is still here");
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', $zonename);
ok($d->find_element_by_xpath('//*[@id="billing_zone_table"]//tr[1]/td[contains(text(), "' . $zonename . '")]'), 'Billing Zone entry is still here');

diag("Try to delete Billing Zone");
$d->move_and_click('//*[@id="billing_zone_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="billing_zone_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing zone successfully deleted',  'Correct Alert was shown');

diag("Check if Billing Zone has been deleted");
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', $zonename);
ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty'), 'Billing Zone entry has been deleted');

diag("Go back to Billing Profile page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Billing', 'link_text')->click();

diag("Open 'Edit Peak Times' page");
$d->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile was found');
$d->move_and_click('//*[@id="billing_profile_table"]//tr[1]//td//div//a[contains(text(), "Off-Peaktimes")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');

diag("Edit Wednesday");
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "Off-peak-times")]'), 'We are on the correct page');
$d->refresh();
$d->move_and_click('//*[@id="content"]//table//tr[3]/td//a[text()[contains(., "Edit")]]', 'xpath', '//*[@id="masthead"]//div//h2[contains(text(), "Off-peak-times")]');

diag("Fill in invalid values");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Wednesday")]'), 'Edit window has been opened');
$d->fill_element('#start', 'css', "invalid");
$d->fill_element('#end', 'css', "value");
$d->find_element('#add', 'css')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "wrong format - must be HH:MM:SS or HH:MM")]'));

diag("Add a Time Definition to Wednesday");
$d->fill_element('#start', 'css', "04:20:00");
$d->fill_element('#end', 'css', "13:37:00");
$d->find_element('#add', 'css')->click();

diag("Add empty Time Definition");
$d->find_element('#add', 'css')->click();
$d->find_element('#mod_close', 'css')->click();

diag("Check Time Definition Details");
ok($d->find_element_by_xpath('//*[@id="content"]/div/table//tr[3]/td[text()[contains(.,"04:20:00")]]'), 'Time Definition 1 is correct');
ok($d->find_element_by_xpath('//*[@id="content"]/div/table//tr[3]/td[text()[contains(.,"13:37:00")]]'), 'Time Definition 2 is correct');
ok($d->find_element_by_xpath('//*[@id="content"]/div/table//tr[3]/td[text()[contains(.,"00:00:00")]]'), 'Time Definition 3 is correct');
ok($d->find_element_by_xpath('//*[@id="content"]/div/table//tr[3]/td[text()[contains(.,"23:59:59")]]'), 'Time Definition 4 is correct');

diag("Create a Date Definition");
$d->find_element('Create Special Off-Peak Date', 'link_text')->click();

diag("Save without entering anything");
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Start Date/Time field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "End Date/Time field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid date format, must be YYYY-MM-DD hh:mm:ss")]'));

diag("Fill in invalid values");
$d->fill_element('#start', 'css', "this should");
$d->fill_element('#end', 'css', "not work");
$d->find_element('#save', 'css')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Could not parse DateTime input. Should be one of (Y-m-d H:M:S, Y-m-d H:M, Y-m-d).")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid date format, must be YYYY-MM-DD hh:mm:ss")]'));

diag("Fill in valid values");
$d->fill_element('#start', 'css', "2008-02-28 04:20:00");
$d->fill_element('#end', 'css', "2008-02-28 13:37:00");
$d->find_element('#save', 'css')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Special offpeak entry successfully created',  'Correct Alert was shown');

diag("Check if Date Definition is correct");
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#date_definition_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', '2008-02-28 04:20:00');
ok($d->find_element_by_xpath('//*[@id="date_definition_table"]//tr[1]/td[contains(text(), "2008-02-28 04:20:00")]'), 'Start Date Definition is correct');
ok($d->find_element_by_xpath('//*[@id="date_definition_table"]//tr[1]/td[contains(text(), "2008-02-28 13:37:00")]'), 'End Date Definition is correct');

diag("Edit Date Definition");
$d->move_and_click('//*[@id="date_definition_table"]/tbody/tr/td[4]/div/a[1]', 'xpath', '//div[contains(@class, "dataTables_filter")]//input');
$d->fill_element('#start', 'css', "2018-01-01 00:00:00");
$d->fill_element('#end', 'css', "2019-01-01 23:59:59");
$d->find_element('#save', 'css')->click();

diag("Check if Date Definition is correct");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Special offpeak entry successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="date_definition_table"]//tr[1]/td[contains(text(), "2018-01-01 00:00:00")]'), 'Start Date Definition is correct');
ok($d->find_element_by_xpath('//*[@id="date_definition_table"]//tr[1]/td[contains(text(), "2019-01-01 23:59:59")]'), 'End Date Definition is correct');

diag("Delete Date Definition");
$d->scroll_to_element($d->find_element('//*[@id="date_definition_table_filter"]/label/input'));
$d->move_and_click('//*[@id="date_definition_table"]/tbody//tr//td//div//a[contains(text(),"Delete")]', 'xpath', '//div[contains(@class, "dataTables_filter")]//input');
$d->find_element('#dataConfirmOK', 'css')->click();

diag("Check if Date Definition has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Special offpeak entry successfully deleted',  'Correct Alert was shown');
ok($d->find_element_by_css('#date_definition_table tr > td.dataTables_empty'), 'Date Definition has been deleted');

diag("Try to NOT delete Billing Profile");
$c->delete_billing_profile($billingname, 1);

diag("Check if Billing Profile is still here");
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);
ok($d->find_element_by_xpath('//*[@id="billing_profile_table"]//tr[1]/td[contains(text(), "' . $billingname . '")]'), 'Billing Profile is still here');

diag("Try to delete Billing Profile");
$c->delete_billing_profile($billingname);

diag("Check if Billing Profile has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing profile successfully terminated',  'Correct Alert was shown');
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Billing Profile has been deleted');

diag("Go to 'Billing Networks' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Billing Networks', 'link_text')->click();

diag("Try to create an empty Billing Network");
$d->find_element('Create Billing Network', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Billing Network Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Blocks field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller was found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="name"]', 'xpath', $billingnetwork);
$d->fill_element('//*[@id="description"]', 'xpath', 'Very nice description');

diag("Fill in invalid IP and subnet mask");
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', 'invalid');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', 'ip');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Ip is no valid IPv4 or IPv6 address.")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid IP address")]'));

diag("Fill in valid IP and subnet mask");
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '127.0.0.1');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '8');
$d->find_element('//*[@id="save"]')->click();

diag("Search Billing Network");
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#networks_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', $billingnetwork);

diag("Check details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing Network successfully created',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "' . $billingnetwork . '")]'), 'Billing Network name is correct');
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "127.0.0.1/8")]'), 'Network block is correct');

diag("Edit Billing Network");
$billingnetwork = ("billing" . int(rand(100000)) . "network");
$d->move_and_click('//*[@id="networks_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="networks_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $billingnetwork);
$d->fill_element('//*[@id="description"]', 'xpath', 'also good description');

diag("Add new network block");
$d->find_element('//*[@id="blocks_add"]')->click();
$d->fill_element('//*[@id="blocks.1.row.ip"]', 'xpath', '10.0.0.138');
$d->fill_element('//*[@id="blocks.1.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="save"]')->click();

diag("Search Billing Network");
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#networks_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', $billingnetwork);

diag("Check Details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing network successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "' . $billingnetwork . '")]'), 'Billing Network name is correct');
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "127.0.0.1/8")]'), 'Network block (IP 1) is correct');
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "10.0.0.138/16")]'), 'Network block (IP 2) is correct');

diag("Try to NOT delete Billing Network");
$d->move_and_click('//*[@id="networks_table"]//tr[1]//td//a[contains(text(), "Terminate")]', 'xpath', '//*[@id="networks_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Billing Network is still here");
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#networks_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', $billingnetwork);
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "' . $billingnetwork . '")]'), 'Billing Network is still here');

diag("Try to delete Billing Network");
$d->move_and_click('//*[@id="networks_table"]//tr[1]//td//a[contains(text(), "Terminate")]', 'xpath', '//*[@id="networks_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Billing Network has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing network successfully terminated',  'Correct Alert was shown');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', $billingnetwork);
ok($d->find_element_by_css('#networks_table tr > td.dataTables_empty', 'css'), 'Billing network has been deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_billing.png");
    }
    $d->quit();
    done_testing;
}