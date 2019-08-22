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

my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $timesetname = ("time" . int(rand(100000)) . "set");
my $groupname = ("group" . int(rand(100000)) . "test");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag("Go to Time Sets page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Time Sets", 'link_text')->click();

diag("Trying to create a empty Time Set");
$d->find_element("Create Time Set Entry", 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->find_element('//*[@id="save"]')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Enter Information");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $timesetname);
$d->find_element('//*[@id="save"]')->click();

diag("Search for our new Timeset");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Timeset entry successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);

diag("Check details");
ok($d->wait_for_text('//*[@id="timeset_table"]/tbody/tr[1]/td[3]', $timesetname), "Name is correct");
ok($d->wait_for_text('//*[@id="timeset_table"]/tbody/tr[1]/td[2]', $resellername), "Reseller is correct");

diag("Edit Timeset");
$timesetname = ("time" . int(rand(100000)) . "set");
$d->move_and_click('//*[@id="timeset_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $timesetname);
$d->find_element('//*[@id="save"]')->click();

diag("Search for our new Timeset");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Timeset entry successfully updated",  "Correct Alert was shown");
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);

diag("Check details");
ok($d->wait_for_text('//*[@id="timeset_table"]/tbody/tr[1]/td[3]', $timesetname), "Name is correct");
ok($d->wait_for_text('//*[@id="timeset_table"]/tbody/tr[1]/td[2]', $resellername), "Reseller is correct");

diag("Go to Events page");
$d->move_and_click('//*[@id="timeset_table"]//tr[1]//td//a[contains(text(), "Events")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');

diag("Trying to create a new Event");
$d->find_element("Create Event", 'link_text')->click();

diag("Fill in invalid Values");
$d->fill_element('//*[@id="comment"]', 'xpath', 'testing invalid content');
$d->fill_element('//*[@id="startdate_datetimepicker"]', 'xpath', 'invalid');
$d->fill_element('//*[@id="starttime_datetimepicker"]', 'xpath', 'stuff');
$d->find_element('//*[@id="save"]')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid datetime, must be in format yy-mm-dd HH:mm:ss")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid time, must be in format HH:mm:ss")]'));

diag("Fill in valid details");
$d->fill_element('//*[@id="comment"]', 'xpath', 'Hello, im a special Event =)');
$d->fill_element('//*[@id="startdate_datetimepicker"]', 'xpath', '2019-01-01');
$d->fill_element('//*[@id="starttime_datetimepicker"]', 'xpath', '12:00:00');
$d->find_element('//*[@id="end.switch.label.control"]')->click();
$d->fill_element('//*[@id="enddate_datetimepicker"]', 'xpath', '2019-06-05');
$d->fill_element('//*[@id="endtime_datetimepicker"]', 'xpath', '12:20:00');
$d->find_element('//*[@id="repeat.freq"]/option[@value="weekly"]')->click();
$d->find_element('//*[@id="byday.label"]')->click();
$d->select_if_unselected('//*[@id="byday.weekdays.0"]');
$d->find_element('//*[@id="save"]')->click();

diag("Search for new Event");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Event entry successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="event_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#event_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="event_table_filter"]/label/input', 'xpath', 'Hello, im a special Event =)');

diag("Check Details");
ok($d->wait_for_text('//*[@id="event_table"]/tbody/tr[1]/td[2]', 'Hello, im a special Event =)'), "Description is correct");
ok($d->wait_for_text('//*[@id="event_table"]/tbody/tr[1]/td[3]', 'every week on Monday from 2019-01-01 12:00:00 to 2019-06-05 12:20:00'), "Date/Time is correct");

diag("Edit Event");
$d->move_and_click('//*[@id="event_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="event_table_filter"]//input');
$d->fill_element('//*[@id="comment"]', 'xpath', 'Very important event');
$d->fill_element('//*[@id="startdate_datetimepicker"]', 'xpath', '2020-06-01');
$d->fill_element('//*[@id="starttime_datetimepicker"]', 'xpath', '12:00:00');
$d->fill_element('//*[@id="enddate_datetimepicker"]', 'xpath', '2020-07-01');
$d->fill_element('//*[@id="endtime_datetimepicker"]', 'xpath', '13:00:00');
$d->find_element('//*[@id="save"]')->click();

diag("Search for Event");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Event entry successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="event_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#event_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="event_table_filter"]/label/input', 'xpath', 'Very important event');

diag("Check Details");
ok($d->wait_for_text('//*[@id="event_table"]/tbody/tr[1]/td[2]', 'Very important event'), "Description is correct");
ok($d->wait_for_text('//*[@id="event_table"]/tbody/tr[1]/td[3]', 'every week on Monday from 2020-06-01 12:00:00 to 2020-07-01 13:00:00'), "Date/Time is correct");

diag("Go to Peering Groups Page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Peerings", 'link_text')->click();

diag("Create a Peering Group");
$d->find_element("Create Peering Group", 'link_text')->click();
$d->fill_element('//*[@id="contractidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contractidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contractidtable_filter"]/label/input', 'xpath', 'default-system@default.invalid');
ok($d->wait_for_text('//*[@id="contractidtable"]/tbody/tr[1]/td[3]', 'default-system@default.invalid'), "Contact found");
$d->select_if_unselected('//*[@id="contractidtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="name"]', 'xpath', $groupname);
$d->fill_element('//*[@id="description"]', 'xpath', 'For Timeset Testing');
$d->fill_element('//*[@id="time_setidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#time_setidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="time_setidtable_filter"]/label/input', 'xpath', $timesetname);
ok($d->wait_for_text('//*[@id="time_setidtable"]/tbody/tr[1]/td[2]', $timesetname), "Time Set found");
$d->select_if_unselected('//*[@id="time_setidtable"]/tbody/tr[1]/td[4]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Search for Peering Group");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering group successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);

diag("Check Peering Group Details");
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[2]', 'default-system@default.invalid'), 'Contact is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Name is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[5]', 'For Timeset Testing'), 'Description is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[6]', $timesetname), 'Time Set is correct');

diag("Delete Peering Group");
$d->move_and_click('//*[@id="sip_peering_group_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="sip_peering_group_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering Group successfully deleted",  "Correct Alert was shown");

diag("Go back to Time set page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Time Sets", 'link_text')->click();

diag("Trying to NOT delete Time set");
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);
ok($d->wait_for_text('//*[@id="timeset_table"]/tbody/tr[1]/td[3]', $timesetname), "Time set was found");
$d->move_and_click('//*[@id="timeset_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Time set is still here");
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);
ok($d->wait_for_text('//*[@id="timeset_table"]/tbody/tr[1]/td[3]', $timesetname), "Time set is still here");

diag("Trying to delete Time set");
$d->move_and_click('//*[@id="timeset_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Time set was deleted");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Timeset entry successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Time set was deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_timeset.png");
    }
    $d->quit();
    done_testing;
}