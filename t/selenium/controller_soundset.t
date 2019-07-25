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
my $soundsetname = ("sound" . int(rand(100000)) . "set");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag('Go to Sound Sets');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Sound Sets", 'link_text')->click();

diag('Trying to create a empty Sound Set');
$d->find_element('Create Sound Set', 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]//td//input');
$d->find_element('//*[@id="save"]')->click();

diag('Check Error Messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), 'Reseller was found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="name"]', 'xpath', $soundsetname);
$d->fill_element('//*[@id="description"]', 'xpath', 'nice desc');
$d->find_element('//*[@id="save"]')->click();

diag('Search Sound Set');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Sound set successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);

diag('Check details');
ok($d->wait_for_text('//*[@id="sound_set_table"]//tr[1]/td[4]', $soundsetname), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "nice desc")]'), 'Description is correct');

diag('Edit Sound Set');
$soundsetname = ("sound" . int(rand(100000)) . "set");
$d->move_and_click('//*[@id="sound_set_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="sound_set_table_filter"]//input');
$d->fill_element('//*[@id="name"]', 'xpath', $soundsetname);
$d->fill_element('//*[@id="description"]', 'xpath', 'very nice desc');
$d->find_element('//*[@id="save"]')->click();

diag('Search Sound Set');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Sound set successfully updated",  "Correct Alert was shown");
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);

diag('Check details');
ok($d->wait_for_text('//*[@id="sound_set_table"]//tr[1]/td[4]', $soundsetname), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "very nice desc")]'), 'Description is correct');

diag('Go to Sound Set files');
$d->move_and_click('//*[@id="sound_set_table"]//tr[1]//td//a[contains(text(), "Files")]', 'xpath', '//*[@id="sound_set_table_filter"]//input');

diag('Edit loop setting for "conference_first"');
$d->find_element('//*[@id="sound_groups"]//div/a[contains(text(), "conference")]')->click();
$d->move_and_click('//table//tr//td[contains(text(), "conference_first")]/..//td//a[contains(text(), "Upload")]', 'xpath', '//*[@id="sound_groups"]//div/a[contains(text(), "conference")]');
$d->select_if_unselected('//*[@id="loopplay"]');
$d->find_element('//*[@id="save"]')->click();

diag('Check if loop setting was enabled');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Sound handle successfully updated",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td//input[@checked="checked"]'), 'loop for conference_first was activated');

diag('Load the default files');
$d->find_element('Load Default Files', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check in "conference" if settings are correct');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Sound set successfully loaded with default files.",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td//input[@checked="checked"]'), 'loop for conference_first is still activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td[not(contains(text(), "conference_first.wav"))]'), 'conference_first.wav was not loaded');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td//input[not(@checked="checked")]'), 'loop for conference_greeting is not activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td[contains(text(), "conference_greeting.wav")]'), 'conference_greeting.wav was loaded');

diag('Load default files again and override everything');
$d->find_element('Load Default Files', 'link_text')->click();
$d->select_if_unselected('//*[@id="replace_existing"]');
$d->find_element('//*[@id="save"]')->click();

diag('Check in "conference" if settings are correct');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Sound set successfully loaded with default files.",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td//input[not(@checked="checked")]'), 'loop for conference_first is not activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td[contains(text(), "conference_first.wav")]'), 'conference_first.wav was loaded');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td//input[not(@checked="checked")]'), 'loop for conference_greeting is not activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td[contains(text(), "conference_greeting.wav")]'), 'conference_greeting.wav was loaded');

diag('Load default files again and loop them');
$d->find_element('Load Default Files', 'link_text')->click();
$d->select_if_unselected('//*[@id="loopplay"]');
$d->select_if_unselected('//*[@id="replace_existing"]');
$d->find_element('//*[@id="save"]')->click();

diag('Check in "conference" if settings are correct');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Sound set successfully loaded with default files.",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td//input[@checked="checked"]'), 'loop for conference_first was activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td[contains(text(), "conference_first.wav")]'), 'conference_first.wav was loaded');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td//input[@checked="checked"]'), 'loop for conference_greeting was activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td[contains(text(), "conference_greeting.wav")]'), 'conference_greeting.wav was loaded');

diag('Trying to NOT Delete Sound Set');
$d->find_element('Back', 'link_text')->click();
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);
ok($d->wait_for_text('//*[@id="sound_set_table"]//tr[1]/td[4]', $soundsetname), "Sound Set was found");
$d->move_and_click('//*[@id="sound_set_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="sound_set_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag('Check if Sound Set is still here');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);
ok($d->wait_for_text('//*[@id="sound_set_table"]//tr[1]/td[4]', $soundsetname), "Sound set is still here");

diag('Trying to Delete Sound Set');
$d->move_and_click('//*[@id="sound_set_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="sound_set_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Sound Set was deleted');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Sound set successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Sound Set was deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_header.png");
    }
    $d->quit();
    done_testing;
}