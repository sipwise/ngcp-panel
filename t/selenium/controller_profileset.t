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

my $setname = ("test" . int(rand(10000)) . "set");
my $clonedsetname = ("test" . int(rand(10000)) . "set");
my $profilename = ("test" . int(rand(10000)) . "profile");
my $cloneprofilename = ("test" . int(rand(10000)) . "profile");
my $contactmail = ("contact" . int(rand(100000)) . '@test.org');
my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $ncosname = ("ncos" . int(rand(100000)) . "level");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_ncos($resellername, $ncosname);

diag("Go to 'Subscriber Profiles' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Subscriber Profiles", 'link_text')->click();

diag("Try to create an empty Subscriber Profile Set");
$d->find_element("Create Subscriber Profile Set", 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Subscriber Profile Set")]'), 'Edit window has been opened');
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));

diag("Enter profile set information");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller was found');
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
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $setname . '")]', $setname), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "This is a description. It describes things")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $resellername .'")]'), 'Reseller is correct');

diag("Edit Subscriber Profile set");
$setname = ("test" . int(rand(10000)) . "set");
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Edit")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Subscriber Profile Set")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $setname);
$d->fill_element('//*[@id="description"]', 'xpath', 'Very Good description here');
$d->find_element('//*[@id="save"]')->click();

diag("Search Subscriber Profile Set");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber profile set successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $setname . '")]', $setname), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "Very Good description here")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $resellername .'")]'), 'Reseller is correct');

diag("Enter 'Profiles' menu");
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Profiles")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');

diag("Try to create an empty Subscriber Profile");
$d->find_element('Create Subscriber Profile', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Subscriber Profile")]'), 'Edit window has been opened');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));

diag("Enter Profile information");
$d->fill_element('//*[@id="name"]', 'xpath', $profilename);
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a description. It describes things');
$d->scroll_to_element($d->find_element('//*[@id="attribute.ncos"]'));
$d->select_if_unselected('//*[@id="attribute.ncos"]', 'xpath');
$d->find_element('//*[@id="save"]')->click();

diag("Search Profile");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber profile successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_table_filter"]/label/input', 'xpath', $profilename);

diag("Check profile details");
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $profilename . '")]', $profilename), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "This is a description. It describes things")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $setname . '")]', $setname), 'Profile Set is correct');

diag("Edit Profile");
$profilename = ("test" . int(rand(10000)) . "profile");
$d->move_and_click('//*[@id="subscriber_profile_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="subscriber_profile_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Subscriber Profile")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $profilename);
$d->fill_element('//*[@id="description"]', 'xpath', 'Very very useful description');
$d->find_element('//*[@id="save"]')->click();

diag("Check profile details");
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $profilename . '")]', $profilename), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "Very very useful description")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $setname . '")]', $setname), 'Profile Set is correct');
$d->capture_screenshot("/results/DEBUG_PS1.png");

diag("Go to 'Profile Preferences' page");
$d->move_and_click('//*[@id="subscriber_profile_table"]//tr[1]/td//a[contains(text(), "Preferences")]', 'xpath', '//*[@id="subscriber_profile_table_filter"]/label/input');

diag("Add NCOS to Profile");
$d->find_element('//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]')->click();
$d->move_and_click('//table//tr//td[contains(text(), "ncos")]//..//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Call Blockings")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "' . "Edit Preference 'NCOS Level'" . '")]'), 'Edit window has been opened');
$d->move_and_click('//*[@id="ncos"]', 'xpath', '//*[@id="mod_edit"]/div/h3[contains(text(), "' . "Edit Preference 'NCOS Level'" . '")]');
$d->find_element('//*[@id="ncos"]//option[contains(text(), "'. $ncosname .'")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if NCOS was applied");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference ncos successfully updated",  'Correct Alert was shown');
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "ncos")]//..//td//select//option[contains(text(), "'. $ncosname .'")][@selected="selected"]'), 'NCOS was applied');
$d->find_element('//*[@id="content"]//div//a[contains(text(), "Back")]')->click();
if($d->find_element_by_xpath('//*[@id="masthead"]//div//h2')->get_text() eq 'Subscriber Profile Sets') { #workaround for back button opening wrong page
    $d->find_element('//*[@id="content"]//div//a[contains(text(), "Back")]')->click();
}

diag("Clone Profile");
$d->move_and_click('//*[@id="subscriber_profile_table"]//tr[1]//td//a[contains(text(), "Clone")]', 'xpath', '//*[@id="subscriber_profile_table_filter"]//input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create cloned Subscriber Profile")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $cloneprofilename);
$d->fill_element('//*[@id="description"]', 'xpath', 'indeed a good description');
$d->find_element('//*[@id="clone"]')->click();

diag("Check if settings are correct");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Subscriber profile successfully cloned",  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_table_filter"]/label/input', 'xpath', $cloneprofilename);
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $cloneprofilename . '")]', $cloneprofilename), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "indeed a good description")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $setname . '")]'), 'Profile Set is correct');

diag("Set clone Profile as default Profile");
$d->move_and_click('//*[@id="subscriber_profile_table"]//tr[1]/td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="subscriber_profile_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Subscriber Profile")]'), 'Edit window has been opened');
$d->select_if_unselected('//*[@id="set_default"]', 'xpath');
$d->find_element('//*[@id="save"]')->click();

diag("Check if cloned Profile is now default");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Subscriber profile successfully updated",  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr/td[contains(text(), "' . $cloneprofilename . '")]//..//td[contains(text(), "1")]'), 'Cloned Profile is now default');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr/td[contains(text(), "' . $profilename . '")]//..//td[contains(text(), "0")]'), 'Original Profile is no longer default');

diag("Delete cloned Profile");
$d->move_and_click('//*[@id="subscriber_profile_table"]//tr//td[contains(text(), "' . $cloneprofilename . '")]//..//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="subscriber_profile_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check original Profile details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Subscriber profile successfully deleted",  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $profilename . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "Very very useful description")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $setname . '")]'), 'Profile Set is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "1")]'), 'Original Profile is now default');
$d->find_element('//*[@id="content"]//div//a[contains(text(), "Back")]')->click();

diag("Clone Subscriber Profile Set");
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $setname . '")]'), 'Profile Set was found');
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Clone")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create cloned Subscriber Profile Set")]'), 'Edit window has been opened');
$d->fill_element('//*[@id="name"]', 'xpath', $clonedsetname);
$d->fill_element('//*[@id="description"]', 'xpath', 'indeed a very interesting description');
$d->find_element('//*[@id="clone"]')->click();

diag("Check cloned Subscriber Profile Set details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Subscriber profile successfully cloned",  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $clonedsetname);
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $clonedsetname . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "indeed a very interesting description")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $resellername .'")]'), 'Reseller is correct');

diag("Check if Profile got cloned");
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Profiles")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $profilename . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "Very very useful description")]'), 'Description is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "' . $clonedsetname . '")]'), 'Profile Set is correct');
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_table"]//tr[1]/td[contains(text(), "1")]'), 'Original Profile is now default');
$d->find_element('//*[@id="content"]//div//a[contains(text(), "Back")]')->click();

diag("Delete Cloned Subscriber Profile Set");
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $clonedsetname);
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $clonedsetname . '")]'), 'Cloned Subscriber Profile Set found');
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if cloned Subscriber Profile Set has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber profile set successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $clonedsetname);
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Cloned Subscriber Profile Set has been deleted');

diag("Try to NOT Delete Subscriber Profile Set");
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $setname . '")]'), 'Subscriber Profile Set was found');
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Subscriber Profile Set is still here");
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Table is empty');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);
ok($d->find_element_by_xpath('//*[@id="subscriber_profile_sets_table"]//tr[1]/td[contains(text(), "' . $setname . '")]'), 'Subscriber Profile Set is still here');

diag("Try to Delete Subscriber Profile Set");
$d->move_and_click('//*[@id="subscriber_profile_sets_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="subscriber_profile_sets_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Subscriber Profile Set has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Subscriber profile set successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="subscriber_profile_sets_table_filter"]/label/input', 'xpath', $setname);
ok($d->find_element_by_css('#subscriber_profile_sets_table tr > td.dataTables_empty'), 'Subscriber Profile Set has been deleted');

$c->delete_ncos($ncosname);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_profileset.png");
    }
    $d->quit();
    done_testing;
}