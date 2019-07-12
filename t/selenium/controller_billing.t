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

diag('Trying to create a empty billing profile');
$d->find_element('Create Billing Profile', 'link_text')->click();

diag("Click 'Save'");
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Handle field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
$d->find_element('//*[@id="mod_close"]')->click();

diag('Search for Test Profile in billing profile');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);

diag('Check if values are correct');
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[3]', $resellername), 'Correct reseller was found');

diag("Open edit dialog for Test Profile");
$d->move_and_click('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Edit")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');

diag("Edit Test Profile");
$d->fill_element('#interval_charge', 'css', '3.2');
$d->find_element('#save', 'css')->click();
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing profile successfully updated',  "Correct Alert was shown");

diag('Open "Fees" for Test Profile');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
$d->move_and_click('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Fees")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');

diag('Go To Billing Zones');
$d->find_element('Edit Zones', 'link_text')->click();

diag('Create a Billing Zone');
$d->find_element('Create', 'link_text')->click();

diag('Press "Save" without entering anything');
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Zone field is required")]'));

diag('Fill in Values');
$d->fill_element('//*[@id="zone"]', 'xpath', $zonename);
$d->fill_element('//*[@id="detail"]', 'xpath', $zonedetailname);
$d->find_element('//*[@id="save"]')->click();
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing Zone successfully created',  "Correct Alert was shown");

diag('Check Billing Zone details');
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', $zonename);
ok($d->wait_for_text('//*[@id="billing_zone_table"]/tbody/tr/td[2]', $zonename), 'Billing Zone name is correct');
ok($d->wait_for_text('//*[@id="billing_zone_table"]/tbody/tr/td[3]', $zonedetailname), 'Billing Zone detail is correct');

diag('Go back to Billing Fees Page');
$d->find_element('Back', 'link_text')->click();

diag('Create a Billing Fee');
$d->find_element('Create Fee Entry', 'link_text')->click();

diag('Press "Save" without entering anything');
$d->unselect_if_selected('//*[@id="billing_zoneidtable"]//tr[1]/td[4]/input');
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Zone field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Destination field is required")]'));

diag('Fill in Values');
$d->select_if_unselected('//*[@id="billing_zoneidtable"]//tr[1]/td[4]/input');
$d->fill_element('#source', 'css', '.*');
$d->fill_element('#destination', 'css', '.+');
$d->find_element('//*[@id="save"]')->click();
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing Fee successfully created!',  "Correct Alert was shown");

diag('Check Billing Fee Details');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', $zonedetailname);
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[2]', '.*'), 'Source Pattern is correct');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[3]', '.+'), 'Destination Pattern is correct');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[4]', 'Regular expression - longest pattern'), 'Match Mode is correct');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[5]', 'out'), 'Direction is correct');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[6]', $zonedetailname), 'Zone Detail is correct');

diag('Edit Billing Fee');
$d->move_and_click('//*[@id="billing_fee_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="billing_fee_table_filter"]/label/input');
$d->find_element('//*[@id="direction"]/option[@value="in"]')->click();
$d->find_element('//*[@id="save"]')->click();
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing fee successfully changed!',  "Correct Alert was shown");

diag('Check Billing Fee Details');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', $zonedetailname);
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[2]', '.*'), 'Source Pattern is correct');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[3]', '.+'), 'Destination Pattern is correct');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[4]', 'Regular expression - longest pattern'), 'Match Mode is correct');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[5]', 'in'), 'Direction is correct');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[6]', $zonedetailname), 'Zone Detail is correct');

diag('Trying to NOT delete Billing Fee');
$d->move_and_click('//*[@id="billing_fee_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="billing_fee_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Billing Fee is still here');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', $zonedetailname);
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[6]', $zonedetailname), 'Billing Fee Entry is still here');

diag('Trying to delete Billing Fee');
$d->move_and_click('//*[@id="billing_fee_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="billing_fee_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing fee successfully deleted!',  "Correct Alert was shown");

diag('Check if Billing Fee was deleted');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', $zonedetailname);
ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty'), 'Billing Fee was deleted');

diag('Go To Billing Zones');
$d->find_element('Edit Zones', 'link_text')->click();

diag('Trying to NOT delete Billing zone');
$d->move_and_click('//*[@id="billing_zone_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="billing_zone_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Billing Zone is still here');
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', $zonename);
ok($d->wait_for_text('//*[@id="billing_zone_table"]/tbody/tr/td[2]', $zonename), 'Billing Zone is still here');

diag('Trying to delete Billing zone');
$d->move_and_click('//*[@id="billing_zone_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="billing_zone_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Billing Zone was deleted');
$d->fill_element('//*[@id="billing_zone_table_filter"]/label/input', 'xpath', $zonename);
ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty'), 'Billing Zone was deleted');

diag("Go back to Billing Profile page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Billing", 'link_text')->click();

diag('Open "Edit Peak Times" for Test Profile');
$d->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
$d->move_and_click('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Off-Peaktimes")]', 'xpath', '//*[@id="billing_profile_table_filter"]//input');

diag("Edit Wednesday");
$d->move_and_click('//table//td[contains(text(),"Wednesday")]/..//a[text()[contains(.,"Edit")]]', 'xpath', '//h3[contains(text(),"Weekdays")]');
ok($d->find_text("Edit Wednesday"), 'Edit dialog was opened');

diag("add/delete a time def to Wednesday");
$d->fill_element('#start', 'css', "04:20:00");
$d->fill_element('#end', 'css', "13:37:00");
$d->find_element('#add', 'css')->click();
$d->find_element('#mod_close', 'css')->click();

diag("check if time def has correct values");
ok($d->find_element_by_xpath('//*[@id="content"]/div/table/tbody/tr[3]/td[text()[contains(.,"04:20:00")]]'), "Time def 1 is correct");
ok($d->find_element_by_xpath('//*[@id="content"]/div/table/tbody/tr[3]/td[text()[contains(.,"13:37:00")]]'), "Time def 2 is correct");

diag("Create a Date Definition");
$d->find_element('Create Special Off-Peak Date', 'link_text')->click();

diag("Click 'Save'");
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Start Date/Time field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "End Date/Time field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid date format, must be YYYY-MM-DD hh:mm:ss")]'));

diag('Fill in invalid values');
$d->fill_element('#start', 'css', "this should");
$d->fill_element('#end', 'css', "not work");
$d->find_element('#save', 'css')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Could not parse DateTime input. Should be one of (Y-m-d H:M:S, Y-m-d H:M, Y-m-d).")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid date format, must be YYYY-MM-DD hh:mm:ss")]'));

diag('Fill in valid values');
$d->fill_element('#start', 'css', "2008-02-28 04:20:00");
$d->fill_element('#end', 'css', "2008-02-28 13:37:00");
$d->find_element('#save', 'css')->click();
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Special offpeak entry successfully created',  "Correct Alert was shown");

diag("Check if created date definition is correct");
$d->scroll_to_element($d->find_element('//div[contains(@class, "dataTables_filter")]//input'));
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#date_definition_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', '2008-02-28 04:20:00');
ok($d->wait_for_text('//*[@id="date_definition_table"]/tbody/tr/td[2]', '2008-02-28 04:20:00'), 'Start Date definition is correct');
ok($d->wait_for_text('//*[@id="date_definition_table"]/tbody/tr/td[3]', '2008-02-28 13:37:00'), 'End Date definition is correct');

diag("Delete my created date definition");
$d->move_and_click('//*[@id="date_definition_table"]/tbody//tr//td//div//a[contains(text(),"Delete")]', 'xpath', '//div[contains(@class, "dataTables_filter")]//input');
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag("Check if created date definition was deleted");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Special offpeak entry successfully deleted',  "Correct Alert was shown");
ok($d->find_element_by_css('#date_definition_table tr > td.dataTables_empty'), 'Table is empty');

diag("Open delete dialog and press cancel");
$c->delete_billing_profile($billingname, 1);

diag("Check if Billing Profile is still here");
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_profile_table_filter"]//input', 'xpath', $billingname);
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');

diag("Open delete dialog and press ok");
$c->delete_billing_profile($billingname);

diag("Check if Billing Profile has been removed");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing profile successfully terminated',  "Correct Alert was shown");
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Billing Profile has been removed');

diag("Go to billing networks page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Billing Networks', 'link_text')->click();

diag("Trying to create a empty billing network");
$d->find_element('Create Billing Network', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Billing Network Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Blocks field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), 'Reseller was found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="name"]', 'xpath', $billingnetwork);
$d->fill_element('//*[@id="description"]', 'xpath', 'Very nice description');

diag('Fill in invalid ip and subnet mask');
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', 'invalid');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', 'ip');
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Ip is no valid IPv4 or IPv6 address.")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid IP address")]'));

diag('Fill in valid ip and subnet mask');
$d->fill_element('//*[@id="blocks.0.row.ip"]', 'xpath', '127.0.0.1');
$d->fill_element('//*[@id="blocks.0.row.mask"]', 'xpath', '8');
$d->find_element('//*[@id="save"]')->click();

diag('Search for Billing network');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#networks_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', $billingnetwork);

diag('Check Details');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing Network successfully created',  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="networks_table"]//tr[1]/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="networks_table"]//tr[1]/td[3]', $billingnetwork), "Billing network name is correct");
ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[contains(text(), "127.0.0.1/8")]'), "Network Block is correct");

diag('Edit Billing Network');
$billingnetwork = ("billing" . int(rand(100000)) . "network");
$d->move_and_click('//*[@id="networks_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="networks_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $billingnetwork);
$d->fill_element('//*[@id="description"]', 'xpath', 'also good description');

diag('Add new billing network block');
$d->find_element('//*[@id="blocks_add"]')->click();
$d->fill_element('//*[@id="blocks.1.row.ip"]', 'xpath', '10.0.0.138');
$d->fill_element('//*[@id="blocks.1.row.mask"]', 'xpath', '16');
$d->find_element('//*[@id="save"]')->click();

diag('Search for Billing network');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#networks_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', $billingnetwork);

diag('Check Details');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing network successfully updated',  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="networks_table"]//tr[1]/td[2]', $resellername), "Reseller is correct");
ok($d->wait_for_text('//*[@id="networks_table"]//tr[1]/td[3]', $billingnetwork), "Billing network name is correct");
#ok($d->find_element_by_xpath('//*[@id="networks_table"]//tr[1]/td[text()[contains(., "127.0.0.1/8, 10.0.0.138/16")]]'), "Network Block is correct");

diag('Try to NOT delete Billing Network');
$d->move_and_click('//*[@id="networks_table"]//tr[1]//td//a[contains(text(), "Terminate")]', 'xpath', '//*[@id="networks_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Billing Network is still here');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#networks_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', $billingnetwork);
ok($d->wait_for_text('//*[@id="networks_table"]//tr[1]/td[3]', $billingnetwork), "Billing Network is still here");

diag('Try to delete Billing Network');
$d->move_and_click('//*[@id="networks_table"]//tr[1]//td//a[contains(text(), "Terminate")]', 'xpath', '//*[@id="networks_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Billing Network has been deleted');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), 'Billing network successfully terminated',  "Correct Alert was shown");
$d->fill_element('//*[@id="networks_table_filter"]/label/input', 'xpath', $billingnetwork);
ok($d->find_element_by_css('#networks_table tr > td.dataTables_empty', 'css'), 'Billing network was deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_billing.png");
    }
    done_testing;
}