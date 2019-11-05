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

diag("Go to 'Sound Sets' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Sound Sets', 'link_text')->click();

diag("Try to create an empty Sound Set");
$d->find_element('Create Sound Set', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Sound Set")]'), 'Edit window has been opened');
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]//td//input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller was found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->fill_element('//*[@id="name"]', 'xpath', $soundsetname);
$d->fill_element('//*[@id="description"]', 'xpath', 'nice desc');
$d->find_element('//*[@id="save"]')->click();

diag("Search Sound Set");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Sound set successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "' . $soundsetname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "nice desc")]'), 'Description is correct');

diag("Edit Sound Set");
$soundsetname = ("sound" . int(rand(100000)) . "set");
$d->move_and_click('//*[@id="sound_set_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="sound_set_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Sound Set")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $soundsetname);
$d->fill_element('//*[@id="description"]', 'xpath', 'very nice desc');
$d->find_element('//*[@id="save"]')->click();

diag("Search Sound Set");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Sound set successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "' . $soundsetname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "very nice desc")]'), 'Description is correct');

diag("Go to 'Sound Set Files' page");
$d->move_and_click('//*[@id="sound_set_table"]//tr[1]//td//a[contains(text(), "Files")]', 'xpath', '//*[@id="sound_set_table_filter"]//input');

diag("Edit loop setting for 'conference_first'");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->move_and_click('//table//tr//td[contains(text(), "conference_first")]/..//td//a[contains(text(), "Upload")]', 'xpath', '//*[@id="sound_groups"]//div/a[contains(text(), "conference")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit conference_first")]'), 'Edit window has been opened');
$d->select_if_unselected('//*[@id="loopplay"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check if loop setting was enabled");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Sound handle successfully updated',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td//input[@checked="checked"]'), 'loop for conference_first was activated');

diag("Load default Files");
$d->find_element('Load Default Files', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Default Files")]'), 'Edit window has been opened');
$d->find_element('//*[@id="save"]')->click();

diag("Check in 'conference' if settings are correct");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Sound set successfully loaded with default files.',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td//input[@checked="checked"]'), 'loop for conference_first is still activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td[not(contains(text(), "conference_first.wav"))]'), 'conference_first.wav was not loaded');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td//input[not(@checked="checked")]'), 'loop for conference_greeting is not activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td[contains(text(), "conference_greeting.wav")]'), 'conference_greeting.wav was loaded');

diag("Load default Files again and override everything");
$d->find_element('Load Default Files', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Default Files")]'), 'Edit window has been opened');
$d->select_if_unselected('//*[@id="replace_existing"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check in 'conference' if settings are correct");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Sound set successfully loaded with default files.',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td//input[not(@checked="checked")]'), 'loop for conference_first is not activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td[contains(text(), "conference_first.wav")]'), 'conference_first.wav was loaded');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td//input[not(@checked="checked")]'), 'loop for conference_greeting is not activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td[contains(text(), "conference_greeting.wav")]'), 'conference_greeting.wav was loaded');

diag("Load default Files again and loop them");
$d->find_element('Load Default Files', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Default Files")]'), 'Edit window has been opened');
$d->select_if_unselected('//*[@id="loopplay"]');
$d->select_if_unselected('//*[@id="replace_existing"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check in 'conference' if settings are correct");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Sound set successfully loaded with default files.',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td//input[@checked="checked"]'), 'loop for conference_first was activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_first")]/..//td[contains(text(), "conference_first.wav")]'), 'conference_first.wav was loaded');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td//input[@checked="checked"]'), 'loop for conference_greeting was activated');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "conference_greeting")]/..//td[contains(text(), "conference_greeting.wav")]'), 'conference_greeting.wav was loaded');

diag("Try to NOT delete Sound Set");
$d->find_element('Back', 'link_text')->click();
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "' . $soundsetname . '")]'), 'Sound Set was found');
$d->move_and_click('//*[@id="sound_set_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="sound_set_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Sound Set is still here");
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);
ok($d->find_element_by_xpath('//*[@id="sound_set_table"]//tr[1]/td[contains(text(), "' . $soundsetname . '")]'), 'Sound set is still here');

diag("Try to delete Sound Set");
$d->move_and_click('//*[@id="sound_set_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="sound_set_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Sound Set has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Sound set successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="sound_set_table_filter"]/label/input', 'xpath', $soundsetname);
ok($d->find_element_by_css('#sound_set_table tr > td.dataTables_empty', 'css'), 'Sound Set has been deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_soundset.png");
    }
    $d->quit();
    done_testing;
}