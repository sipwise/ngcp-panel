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
my $rulesetname = ("rule" . int(rand(100000)) . "test");
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag('Go to Rewrite Rule Sets page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Rewrite Rule Sets', 'link_text')->click();

diag('Trying to create a empty Rewrite Rule Set');
$d->find_element('Create Rewrite Rule Set', 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input');
$d->find_element('//*[@id="save"]')->click();

diag('Check Error Messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag('Create a legit Rewrite Rule Set');
$d->find_element('#mod_close', 'css')->click();
$c->create_rw_ruleset($rulesetname, $resellername);

diag('Search for our new Rewrite Rule Set');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule set successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);

diag('Check Rewrite Rule Set Details');
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[2]', $resellername), 'Reseller Name is correct');
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[3]', $rulesetname), 'Ruleset Name is correct');
ok($d->find_element_by_xpath('//*[@id="rewrite_rule_set_table"]//tr[1]//td[contains(text(), "For testing purposes")]'), 'Description is correct');

diag('Edit Rewrite Rule Set');
$rulesetname = ("rule" . int(rand(100000)) . "test");
$d->move_and_click('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Edit")]', 'xpath', '//*[@id="rewrite_rule_set_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $rulesetname);
$d->fill_element('//*[@id="description"]', 'xpath', 'For very testing purposes');
$d->find_element('//*[@id="save"]')->click();

diag('Search for our new Rewrite Rule Set');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule set successfully updated",  "Correct Alert was shown");
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);

diag('Check Rewrite Rule Set Details');
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[2]', $resellername), 'Reseller Name is correct');
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[3]', $rulesetname), 'Ruleset Name is correct');
ok($d->find_element_by_xpath('//*[@id="rewrite_rule_set_table"]//tr[1]//td[contains(text(), "For very testing purposes")]'), 'Description is correct');

diag('Go To Rewrite Rule Set Rules');
$d->move_and_click('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Rules")]', 'xpath', '//*[@id="rewrite_rule_set_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "Rewrite Rules")]'), "We are on the correct Page");
sleep 1;

diag('Create a new empty Rule for Caller');
$d->find_element('Create Rewrite Rule', 'link_text')->click;
$d->find_element('//*[@id="save"]')->click();

diag('Check Error Messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Match pattern field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Replacement Pattern field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));

diag('Fill in invalid info');
$d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(21|\+)([4-9][0-9]+)$');
$d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\4');
$d->find_element('//*[@id="save"]')->click();

diag('Check Error Messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Match pattern and Replace Pattern do not work together")]'));

diag('Fill in valid Values');
$d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
$d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\2');
$d->fill_element('//*[@id="description"]', 'xpath', 'Not International to E.164');
$d->find_element('//*[@id="field"]/option[@value="caller"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check if Rule has been created');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule successfully created",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "Not International to E.164")]'), "Description is correct");

diag('Edit Rule for Caller');
$d->move_and_click('//*[@id="collapse_icaller"]//table//tr[1]//td//a[text()[contains(., "Edit")]]', 'xpath', '//*[@id="masthead"]//div/h2');
$d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
$d->find_element('//*[@id="save"]')->click();

diag('Check if Rule has been edited');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule successfully updated",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "International to E.164")]'), "Description is correct");

diag('Create a new Rule for Callee');
$d->find_element('Create Rewrite Rule', 'link_text')->click;
$d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
$d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\2');
$d->fill_element('//*[@id="description"]', 'xpath', 'Not International to E.164');
$d->find_element('//*[@id="field"]/option[@value="callee"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check if Rule has been created');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule successfully created",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "Not International to E.164")]'), "Description is correct");

diag('Edit Rule for Callee');
$d->move_and_click('//*[@id="collapse_icallee"]//table//tr[1]//td//a[text()[contains(., "Edit")]]', 'xpath', '//*[@id="masthead"]//div/h2');
$d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
$d->find_element('//*[@id="save"]')->click();

diag('Check if Rule has been edited');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule successfully updated",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "International to E.164")]'), "Description is correct");

diag('Testing if rules can be reordered');
diag('Create a new rule for Caller');
$d->find_element('Create Rewrite Rule', 'link_text')->click;
$d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
$d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\1');
$d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
$d->find_element('//*[@id="field"]/option[@value="caller"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Test if new entry moves up if up arrow is clicked');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule successfully created",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->find_element('//*[@id="collapse_icaller"]/div/table/tbody/tr/td[contains(text(), "\1")]/../td//a//i[@class="icon-arrow-up"]')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]/td[contains(text(), "\1")]'), "Replacement Pattern is correct");
=pod
diag('Delete Rule');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->move_and_click('//*[@id="collapse_icaller"]//table//tr[2]//td//a[text()[contains(., "Delete")]]', 'xpath', '//*[@id="masthead"]//div/h2');
$d->find_element('//*[@id="dataConfirmOK"]')->click();
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule successfully deleted",  "Correct Alert was shown");
=cut
diag('Go Back to the Rewrite Rule set Page');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Rewrite Rule Sets', 'link_text')->click();

diag('Trying to clone a ruleset');
my $rulesetclonename = ("rule" . int(rand(100000)) . "test");
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[3]', $rulesetname), 'Ruleset was found');
$d->move_and_click('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Clone")]', 'xpath', '//*[@id="rewrite_rule_set_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $rulesetclonename);
$d->fill_element('//*[@id="description"]', 'xpath', 'Im a clone, beep boop');
$d->find_element('//*[@id="clone"]')->click();

diag('Search for the cloned Rewrite Rule Set');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule set successfully cloned",  "Correct Alert was shown");
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetclonename);

diag('Check Rewrite Rule Set Details');
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[2]', $resellername), 'Reseller Name is correct');
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[3]', $rulesetclonename), 'Ruleset Name is correct');
ok($d->find_element_by_xpath('//*[@id="rewrite_rule_set_table"]//tr[1]//td[contains(text(), "Im a clone, beep boop")]'), 'Description is correct');
$d->move_and_click('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Rules")]', 'xpath', '//*[@id="rewrite_rule_set_table_filter"]/label/input');

diag('Check if Caller got properly cloned');
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "\1")]'), "Replacement Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "International to E.164")]'), "Description is correct");

diag('Check if Callee got properly cloned');
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "International to E.164")]'), "Description is correct");

diag('Trying to add the ruleset to a domain');
$c->create_domain($domainstring, $resellername);

diag('Enter Domain Preferences');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr/td[3]', $domainstring), 'Entry was found');
$d->move_and_click('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Preferences")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');

diag('Add ruleset to a domain');
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('Number Manipulations', 'link_text'));
$d->move_and_click('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td/div//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Number Manipulations")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");
$d->find_element('//*[@id="rewrite_rule_set"]/option[contains(text(), "' . $rulesetname . '")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check if correct ruleset has been selected');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference rewrite_rule_set successfully updated",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td[4]/select/option[@selected="selected"]', $rulesetname), 'rewrite_rule_set value has been set');

diag('Delete Domain');
$c->delete_domain($domainstring);

diag("Open delete dialog and press cancel");
$c->delete_rw_ruleset($rulesetname, 1);
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset is still here');

diag('Open delete dialog and press delete');
$c->delete_rw_ruleset($rulesetname, 0);
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Rewrite rule set successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Ruleset was deleted');

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_rw_ruleset.png");
    }
    $d->quit();
    done_testing;
}