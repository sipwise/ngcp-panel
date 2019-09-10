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
my $headername = ("header" . int(rand(100000)) . "manipuls");
my $headerrule = ("header" . int(rand(100000)) . "rule");
my $headercondition = ("header" . int(rand(100000)) . "condition");
my $headeraction = ("header" . int(rand(100000)) . "action");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);
$c->create_rw_ruleset($rulesetname, $resellername);

diag('Go to Header Manipulations');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Header Manipulations", 'link_text')->click();

diag('Try to create a empty Header Rule Set');
$d->find_element("Create Header Rule Set", 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $headername);
$d->fill_element('//*[@id="description"]' , 'xpath', 'This is a nice description');
$d->find_element('//*[@id="save"]')->click();

diag('Search for Header Rule set');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule set successfully created',  "Correct Alert was shown");
$d->fill_element('//*[@id="header_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#header_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="header_rule_set_table_filter"]/label/input', 'xpath', $headername);

diag('Check Details');
ok($d->find_element_by_xpath('//*[@id="header_rule_set_table"]//tr[1]//td[contains(text(), "' . $resellername . '")]'), "Reseller is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_set_table"]//tr[1]//td[contains(text(), "' . $headername . '")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_set_table"]//tr[1]//td[contains(text(), "This is a nice description")]'), "Reseller is correct");

diag('Edit Header Rule set');
$headername = ("header" . int(rand(100000)) . "manipuls");
$d->move_and_click('//*[@id="header_rule_set_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="header_rule_set_table_filter"]/label/input');
$d->fill_element('//*[@id="name"]', 'xpath', $headername);
$d->fill_element('//*[@id="description"]' , 'xpath', 'This is a very nice description');
$d->find_element('//*[@id="save"]')->click();

diag('Search for Header Rule set');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule set successfully updated',  "Correct Alert was shown");
$d->fill_element('//*[@id="header_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#header_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="header_rule_set_table_filter"]/label/input', 'xpath', $headername);

diag('Check Details');
ok($d->find_element_by_xpath('//*[@id="header_rule_set_table"]//tr[1]//td[contains(text(), "' . $resellername . '")]'), "Reseller is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_set_table"]//tr[1]//td[contains(text(), "' . $headername . '")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_set_table"]//tr[1]//td[contains(text(), "This is a very nice description")]'), "Reseller is correct");

diag('Go to Header Ruleset Rules');
$d->move_and_click('//*[@id="header_rule_set_table"]//tr[1]//td//a[contains(text(), "Rules")]', 'xpath', '//*[@id="header_rule_set_table_filter"]/label/input');

diag('Try to create a empty Header Rule');
$d->find_element("Create Header Rule", 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Description field is required")]'));

diag('Fill in Values');
$d->fill_element('//*[@id="name"]', 'xpath', $headerrule);
$d->fill_element('//*[@id="description"]', 'xpath', 'this is a nice description');+
$d->find_element('//*[@id="save"]')->click();

diag('Check Details');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule successfully created',  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[contains(text(), "100")]'), "Priority is correct");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[contains(text(), "' . $headerrule . '")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[contains(text(), "this is a nice description")]'), "Reseller is correct");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[contains(text(), "inbound")]'), "Direction is correct");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[6][contains(text(), "0")]'), "Stopper is correct");
ok($d->wait_for_text('//*[@id="header_rules_table"]//tr[1]//td[7]', '1'), "Enabled is correct");

diag('Edit Header Rule');
$headerrule = ("header" . int(rand(100000)) . "rule");
$d->move_and_click('//*[@id="header_rules_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="header_rules_table_filter"]/label/input');
$d->fill_element('//*[@id="priority"]', 'xpath', '1');
$d->fill_element('//*[@id="name"]', 'xpath', $headerrule);
$d->find_element('//*[@id="direction"]/option[@value="outbound"]')->click();
$d->fill_element('//*[@id="description"]', 'xpath', 'this is a very nice description');
$d->select_if_unselected('//*[@id="stopper"]');
$d->find_element('//*[@id="save"]')->click();

diag('Check Details');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule successfully updated',  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[contains(text(), "1")]'), "Priority is correct");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[contains(text(), "' . $headerrule . '")]'), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[contains(text(), "this is a very nice description")]'), "Reseller is correct");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[contains(text(), "outbound")]'), "Direction is correct");
ok($d->find_element_by_xpath('//*[@id="header_rules_table"]//tr[1]//td[6][contains(text(), "1")]'), "Stopper is correct");
ok($d->wait_for_text('//*[@id="header_rules_table"]//tr[1]//td[7]', '1'), "Enabled is correct");

diag('Create a Second Header Rule');
$d->find_element("Create Header Rule", 'link_text')->click();
$d->fill_element('//*[@id="name"]', 'xpath', 'second');
$d->fill_element('//*[@id="description"]', 'xpath', 'this is a nice description');+
$d->find_element('//*[@id="save"]')->click();

diag('Move new entry up');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule successfully created',  "Correct Alert was shown");
$d->refresh();
$d->move_and_click('//*[@id="header_rules_table"]//tr[2]//td//a[1]', 'xpath', '//*[@id="header_rules_table_filter"]/label/input');

diag('Check if Entry has moved up');
ok($d->wait_for_text('//*[@id="header_rules_table"]//tr[1]/td[3]', 'second'), "Entry has been moved");

diag('Delete Second Header Rule');
$d->fill_element('//*[@id="header_rules_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#header_rules_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="header_rules_table_filter"]//input', 'xpath', 'second');
ok($d->wait_for_text('//*[@id="header_rules_table"]//tr[1]//td[3]', 'second'), "Header Rule was found");
$d->move_and_click('//*[@id="header_rules_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="header_rules_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Header Rule was deleted');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule successfully deleted',  "Correct Alert was shown");
$d->fill_element('//*[@id="header_rules_table_filter"]//input', 'xpath', 'second');
ok($d->find_element_by_css('#header_rules_table tr > td.dataTables_empty', 'css'), 'Header Rule was deleted');

diag('Go to Rule Conditions');
$d->fill_element('//*[@id="header_rules_table_filter"]//input', 'xpath', $headerrule);
$d->move_and_click('//*[@id="header_rules_table"]//tr[1]//td//a[contains(text(), "Conditions")]', 'xpath', '//*[@id="header_rules_table_filter"]/label/input');
ok($d->wait_for_text('//*[@id="masthead"]/div/div/div/h2', "Header Rule Conditions for $headerrule"), "We are on the correct page");

diag('Trying to create a empty Header Rule Condition');
$d->find_element("Create Header Rule Condition", 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check if errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="match_name"]', 'xpath', $headercondition);
$d->find_element('//*[@id="rwr_set"]/option[contains(text(), "' . $rulesetname . '")]')->click();
$d->find_element('//*[@id="rwr_dp"]/option[@value="caller_in_dpid"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check Details');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule condition successfully created',  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="header_rule_conditions_table"]//tr[1]//td[4]', $headercondition), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "header")]'), "Match is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "full")]'), "Part is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "is")]'), "Expression is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "input")]'), "Type is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "' . $rulesetname . '")]'), "Rewrite Rule set is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "caller_in")]'), "Ruleset Direction is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "1")]'), "Condition is enabled");

diag('Edit Condition');
$headercondition = ("header" . int(rand(100000)) . "condition");
$d->move_and_click('//*[@id="header_rule_conditions_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="header_rule_conditions_table_filter"]//input');
$d->find_element('//*[@id="match_type"]/option[@value="avp"]')->click();
$d->find_element('//*[@id="match_part"]/option[@value="port"]')->click();
$d->fill_element('//*[@id="match_name"]', 'xpath', $headercondition);
$d->find_element('//*[@id="expression"]/option[@value="matches"]')->click();
$d->select_if_unselected('//*[@id="expression_negation"]');
$d->find_element('//*[@id="value_type"]/option[@value="preference"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="value_add"]'));
$d->unselect_if_selected('//*[@id="enabled"]');
$d->find_element('//*[@id="rwr_dp"]/option[@value="callee_in_dpid"]')->click();
$d->find_element('//*[@id="value_add"]')->click();
$d->fill_element('//*[@id="values.0.value"]', 'xpath', 'randomvalue');
$d->find_element('//*[@id="save"]')->click();

diag('Check Details');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule condition successfully updated',  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="header_rule_conditions_table"]//tr[1]//td[4]', $headercondition), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "avp")]'), "Match is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "port")]'), "Part is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "! matches")]'), "Expression is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "preference")]'), "Type is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "randomvalue")]'), "Value is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "' . $rulesetname . '")]'), "Rewrite Rule set is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "callee_in")]'), "Ruleset Direction is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_conditions_table"]//tr[1]//td[contains(text(), "0")]'), "Condition is disabled");

diag('Delete Header Rule Condition');
$d->fill_element('//*[@id="header_rule_conditions_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#header_rule_conditions_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="header_rule_conditions_table_filter"]//input', 'xpath', $headercondition);
ok($d->wait_for_text('//*[@id="header_rule_conditions_table"]//tr[1]//td[4]', $headercondition), "Header Rule Condition was found");
$d->move_and_click('//*[@id="header_rule_conditions_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="header_rule_conditions_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Header Rule Condition was deleted');
ok($d->find_element_by_css('#header_rule_conditions_table tr > td.dataTables_empty', 'css'), 'Header Rule Condition was deleted');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule condition successfully deleted',  "Correct Alert was shown");

diag('Go to Header Rule Actions');
$d->find_element('Actions', 'link_text')->click();

diag('Trying to create a empty Header Rule Action');
$d->find_element('Create Header Rule Action', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check if Errors show up');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Header field is required")]'));

diag('Fill in values');
$d->fill_element('//*[@id="c_header"]', 'xpath', $headeraction);
$d->find_element('//*[@id="value_part"]/option[@value="domain"]')->click();
$d->find_element('//*[@id="rwr_set"]/option[contains(text(), "' . $rulesetname . '")]')->click();
$d->find_element('//*[@id="rwr_dp"]/option[@value="caller_in_dpid"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check Details');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule action successfully created',  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="header_rule_actions_table"]/tbody/tr[1]/td[3]', $headeraction), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "full")]'), "Header Part is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "set")]'), "Type is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "domain")]'), "Value Part is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "' . $rulesetname . '")]'), "Rewrite Rule set is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "caller_in")]'), "Ruleset Direction is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "1")]'), "Action is Enabled");

diag('Edit Header Rule Action');
$headeraction = ("header" . int(rand(100000)) . "action");
$d->move_and_click('//*[@id="header_rule_actions_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="header_rule_actions_table_filter"]//input');
$d->fill_element('//*[@id="c_header"]', 'xpath', $headeraction);
$d->find_element('//*[@id="header_part"]/option[@value="port"]')->click();
$d->find_element('//*[@id="action_type"]/option[@value="add"]')->click();
$d->find_element('//*[@id="value_part"]/option[@value="username"]')->click();
$d->fill_element('//*[@id="value"]', 'xpath', 'randomvalue');
$d->scroll_to_element($d->find_element('//*[@id="enabled"]'));
$d->find_element('//*[@id="rwr_dp"]/option[@value="callee_in_dpid"]')->click();
$d->unselect_if_selected('//*[@id="enabled"]');
$d->find_element('//*[@id="save"]')->click();

diag('Check Details');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule action successfully updated',  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="header_rule_actions_table"]/tbody/tr[1]/td[3]', $headeraction), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "port")]'), "Header Part is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "add")]'), "Type is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "username")]'), "Value Part is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "' . $rulesetname . '")]'), "Rewrite Rule set is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "callee_in")]'), "Ruleset Direction is correct");
ok($d->find_element_by_xpath('//*[@id="header_rule_actions_table"]//tr[1]//td[contains(text(), "0")]'), "Action is Disabled");

diag('Create a second Header Rule action');
$d->find_element('Create Header Rule Action', 'link_text')->click();
$d->fill_element('//*[@id="c_header"]', 'xpath', 'second');
$d->find_element('//*[@id="save"]')->click();

diag('Move new entry up');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule action successfully created',  "Correct Alert was shown");
$d->refresh();
$d->move_and_click('//*[@id="header_rule_actions_table"]//tr[2]//td//a[1]', 'xpath', '//*[@id="header_rule_actions_table_filter"]//input');

diag('Check if Entry has moved up');
ok($d->wait_for_text('//*[@id="header_rule_actions_table"]//tr[1]/td[3]', 'second'), "Entry has been moved");

diag('Delete Header Rule Action');
$d->fill_element('//*[@id="header_rule_actions_table_filter"]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#header_rule_actions_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="header_rule_actions_table_filter"]//input', 'xpath', $headeraction);
ok($d->wait_for_text('//*[@id="header_rule_actions_table"]//tr[1]//td[3]', $headeraction), "Header Rule Condition was found");
$d->move_and_click('//*[@id="header_rule_actions_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="header_rule_actions_table_filter"]//input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Header Rule Action was deleted');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule action successfully deleted',  "Correct Alert was shown");
$d->fill_element('//*[@id="header_rule_actions_table_filter"]//input', 'xpath', $headeraction);
ok($d->find_element_by_css('#header_rule_actions_table tr > td.dataTables_empty', 'css'), 'Header Rule Condition was deleted');

diag('Go back to Header Manipulations');
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Header Manipulations", 'link_text')->click();

diag('Delete Header Rule set');
$d->fill_element('//*[@id="header_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#header_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="header_rule_set_table_filter"]/label/input', 'xpath', $headername);
ok($d->find_element_by_xpath('//*[@id="header_rule_set_table"]//tr[1]//td[contains(text(), "' . $headername . '")]'), "Header Rule set was found");
$d->move_and_click('//*[@id="header_rule_set_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="header_rule_set_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag('Check if Header Rule set was deleted');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Header rule set successfully deleted',  "Correct Alert was shown");
$d->fill_element('//*[@id="header_rule_set_table_filter"]/label/input', 'xpath', $headername);
ok($d->find_element_by_css('#header_rule_set_table tr > td.dataTables_empty', 'css'), 'Header Rule set was deleted');

$c->delete_rw_ruleset($rulesetname);
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