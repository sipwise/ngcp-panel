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

diag("Go to 'Time Sets' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Time Sets', 'link_text')->click();

diag("Try to create an empty Time Set");
$d->find_element('Create Time Set Entry', 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Enter information");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $timesetname);
$d->find_element('//*[@id="save"]')->click();

diag("Search Time Set");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Timeset entry successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="timeset_table"]//tr[1]/td[contains(text(), "' . $timesetname . '")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="timeset_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), "Reseller is correct");

diag("Edit Time Set");
$timesetname = ("time" . int(rand(100000)) . "set");
$d->move_and_click('//*[@id="timeset_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $timesetname);
$d->find_element('//*[@id="save"]')->click();

diag("Search Time Set");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Timeset entry successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="timeset_table"]//tr[1]/td[contains(text(), "' . $timesetname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="timeset_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');

diag("Go to 'Events' page");
$d->move_and_click('//*[@id="timeset_table"]//tr[1]//td//a[contains(text(), "Events")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');

diag("Try to create a new Event");
$d->find_element("Create Event", 'link_text')->click();

diag("Fill in invalid values");
$d->fill_element('//*[@id="comment"]', 'xpath', 'testing invalid content');
$d->fill_element('//*[@id="startdate_datetimepicker"]', 'xpath', 'invalid');
$d->fill_element('//*[@id="starttime_datetimepicker"]', 'xpath', 'stuff');
$d->find_element('//*[@id="repeat.freq"]/option[@value="daily"]')->click();
$d->find_element('//*[@id="byday.label"]')->click();
$d->fill_element('//*[@id="byday.weekdaynumber"]', 'xpath', 'invalid stuff');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid datetime, must be in format yy-mm-dd HH:mm:ss")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Invalid time, must be in format HH:mm:ss")]'));

diag("Fill in values");
$d->fill_element('//*[@id="comment"]', 'xpath', 'Hello, im a special Event =)');
$d->fill_element('//*[@id="startdate_datetimepicker"]', 'xpath', '2019-01-01');
$d->fill_element('//*[@id="starttime_datetimepicker"]', 'xpath', '12:00:00');
$d->find_element('//*[@id="end.switch.label.control"]')->click();
$d->fill_element('//*[@id="enddate_datetimepicker"]', 'xpath', '2019-06-05');
$d->fill_element('//*[@id="endtime_datetimepicker"]', 'xpath', '12:20:00');
$d->select_if_unselected('//*[@id="byday.weekdays.0"]');
$d->find_element('//*[@id="byday.weekdaynumber"]')->clear();
$d->find_element('//*[@id="save"]')->click();

diag("Search Event");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Event entry successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="event_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#event_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="event_table_filter"]/label/input', 'xpath', 'Hello, im a special Event =)');

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="event_table"]//tr[1]/td[contains(text(), "Hello, im a special Event =)")]'), "Description is correct");
ok($d->find_element_by_xpath('//*[@id="event_table"]//tr[1]/td[contains(text(), "every day on Monday from 12:00:00 to 12:20:00")]'), "Date/Time is correct");

diag("Edit Event");
$d->move_and_click('//*[@id="event_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="event_table_filter"]//input');
$d->fill_element('//*[@id="comment"]', 'xpath', 'Very important event');
$d->fill_element('//*[@id="startdate_datetimepicker"]', 'xpath', '2020-06-01');
$d->fill_element('//*[@id="starttime_datetimepicker"]', 'xpath', '12:00:00');
$d->fill_element('//*[@id="enddate_datetimepicker"]', 'xpath', '2020-07-01');
$d->fill_element('//*[@id="endtime_datetimepicker"]', 'xpath', '13:00:00');
$d->unselect_if_selected('//*[@id="byday.weekdays.0"]');
$d->fill_element('//*[@id="byday.weekdaynumber"]', 'xpath', '+1FR');
$d->find_element('//*[@id="save"]')->click();

diag("Check details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Event entry successfully created',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="event_table"]//tr[1]/td[contains(text(), "Very important event")]'), "Description is correct");
ok($d->find_element_by_xpath('//*[@id="event_table"]//tr[1]/td[contains(text(), "every day on the 1st Friday from 12:00:00 to 13:00:00")]'), "Date/Time is correct");

diag("Go to 'Peering Groups' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Peerings', 'link_text')->click();

diag("Create a Peering Group and add Time Set to Peering Group");
$d->find_element("Create Peering Group", 'link_text')->click();
$d->fill_element('//*[@id="contractidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contractidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contractidtable_filter"]/label/input', 'xpath', 'default-system@default.invalid');
ok($d->find_element_by_xpath('//*[@id="contractidtable"]//tr[1]/td[contains(text(), "default-system@default.invalid")]'), "Contact found");
$d->select_if_unselected('//*[@id="contractidtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="name"]', 'xpath', $groupname);
$d->fill_element('//*[@id="description"]', 'xpath', 'For Timeset Testing');
$d->fill_element('//*[@id="time_setidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#time_setidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="time_setidtable_filter"]/label/input', 'xpath', $timesetname);
ok($d->find_element_by_xpath('//*[@id="time_setidtable"]//tr[1]/td[contains(text(), "' . $timesetname . '")]'), 'Time Set found');
$d->select_if_unselected('//*[@id="time_setidtable"]/tbody/tr[1]/td[4]/input');
$d->find_element('//*[@id="save"]')->click();

diag("Search Peering Group");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Peering group successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);

diag("Check Peering Group details");
ok($d->find_element_by_xpath('//*[@id="sip_peering_group_table"]//tr[1]/td[contains(text(), "default-system@default.invalid")]'), 'Contact is correct');
ok($d->find_element_by_xpath('//*[@id="sip_peering_group_table"]//tr[1]/td[contains(text(), "' . $groupname . '")]', $groupname), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="sip_peering_group_table"]//tr[1]/td[contains(text(), "For Timeset Testing")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="sip_peering_group_table"]//tr[1]/td[contains(text(), "' . $timesetname . '")]', $timesetname), 'Time Set is correct');

diag("Delete Peering Group");
$d->move_and_click('//*[@id="sip_peering_group_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="sip_peering_group_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Peering Group successfully deleted',  'Correct Alert was shown');

diag("Go to 'Time Sets' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Time Sets', 'link_text')->click();

diag("Try to NOT delete Time Set");
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);
ok($d->find_element_by_xpath('//*[@id="timeset_table"]//tr[1]/td[contains(text(), "' . $timesetname . '")]'), 'Time Set was found');
$d->move_and_click('//*[@id="timeset_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Time Set is still here");
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);
ok($d->find_element_by_xpath('//*[@id="timeset_table"]//tr[1]/td[contains(text(), "' . $timesetname . '")]'), 'Time Set is still here');

diag("Trying to delete Time Set");
$d->move_and_click('//*[@id="timeset_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Time Set was deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Timeset entry successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);
ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Time Set was deleted');

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