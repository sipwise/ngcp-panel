use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

sub ctr_timeset {
    my ($port) = @_;
    my $d = Selenium::Collection::Functions::create_driver($port);
    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $resellername = ("reseller" . int(rand(100000)) . "test");
    my $contractid = ("contract" . int(rand(100000)) . "test");
    my $timesetname = ("time" . int(rand(100000)) . "set");

    $c->login_ok();
    $c->create_reseller_contract($contractid);
    $c->create_reseller($resellername, $contractid);

    diag("Go to Time Sets page");
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Time Sets", 'link_text')->click();

    diag("Trying to create a new Time Set");
    $d->find_element("Create Time Set Entry", 'link_text')->click();

    diag("Enter Information");
    $d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
    $d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
    $d->fill_element('//*[@id="name"]', 'xpath', $timesetname);
    $d->find_element('//*[@id="save"]')->click();

    diag("Search for our new Timeset");
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

    diag("Fill in details");
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
    $d->fill_element('//*[@id="event_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#event_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="event_table_filter"]/label/input', 'xpath', 'Hello, im a special Event =)');

    diag("Check Details");
    ok($d->wait_for_text('//*[@id="event_table"]/tbody/tr[1]/td[2]', 'Hello, im a special Event =)'), "Description is correct");
    ok($d->find_element_by_xpath('//*[@id="event_table"]/tbody/tr[1]/td[contains(text(), "2019-01-01 12:00:00"]'), "Start Date/Time is correct");
    ok($d->find_element_by_xpath('//*[@id="event_table"]/tbody/tr[1]/td[contains(text(), "2019-06-05 12:20:00"]'), "End Date/Time is correct");

    diag("Go back to Time set page");
    $d->find_element("Back", 'link_text')->click();

    diag("Trying to delete Time set");
    $d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);
    ok($d->wait_for_text('//*[@id="timeset_table"]/tbody/tr[1]/td[3]', $timesetname), "Time set was found");
    $d->move_and_click('//*[@id="timeset_table"]//tr[1]/td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="timeset_table_filter"]/label/input');
    $d->find_element('//*[@id="dataConfirmOK"]')->click();

    diag("Check if Time set was deleted");
    $d->fill_element('//*[@id="timeset_table_filter"]/label/input', 'xpath', $timesetname);
    ok($d->find_element_by_css('#timeset_table tr > td.dataTables_empty', 'css'), 'Time set was deleted');

};

if(! caller) {
    ctr_timeset();
    done_testing;
}