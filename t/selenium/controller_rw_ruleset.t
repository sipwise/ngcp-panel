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
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);

diag('Check Rewrite Rule Set Details');
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[2]', $resellername), 'Reseller Name is correct');
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]//tr[1]/td[3]', $rulesetname), 'Ruleset Name is correct');
ok($d->find_element_by_xpath('//*[@id="rewrite_rule_set_table"]//tr[1]//td[contains(text(), "For very testing purposes")]'), 'Description is correct');

diag('Create a new empty Rule for Caller');
$d->move_and_click('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Rules")]', 'xpath', '//*[@id="rewrite_rule_set_table_filter"]/label/input');
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
$d->find_element('Inbound Rewrite Rules for Caller', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "Not International to E.164")]'), "Description is correct");

diag('Edit Rule for Caller');
$d->move_and_click('//*[@id="collapse_icaller"]//table//tr[1]//td//a[text()[contains(., "Edit")]]', 'xpath', '//*[@id="masthead"]//div/h2');
$d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
$d->find_element('//*[@id="save"]')->click();

diag('Check if Rule has been edited');
$d->find_element('Inbound Rewrite Rules for Caller', 'link_text')->click();
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
$d->find_element('Inbound Rewrite Rules for Callee', 'link_text')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "Not International to E.164")]'), "Description is correct");

diag('Edit Rule for Callee');
$d->move_and_click('//*[@id="collapse_icallee"]//table//tr[1]//td//a[text()[contains(., "Edit")]]', 'xpath', '//*[@id="masthead"]//div/h2');
$d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
$d->find_element('//*[@id="save"]')->click();

diag('Check if Rule has been edited');
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
$d->find_element('Inbound Rewrite Rules for Caller', 'link_text')->click();
$d->find_element('//*[@id="collapse_icaller"]/div/table/tbody/tr/td[contains(text(), "\1")]/../td//a//i[@class="icon-arrow-up"]')->click();
ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]/td[contains(text(), "\1")]'), "Replacement Pattern is correct");

diag('Trying to add the ruleset to a domain');
$c->create_domain($domainstring, $resellername);

diag('Enter Domain Preferences');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr/td[3]', $domainstring), 'Entry was found');
$d->move_and_click('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Preferences")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');

diag('Add ruleset to a domain');
$d->find_element('Number Manipulations', 'link_text')->click();
$d->move_and_click('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td/div//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Number Manipulations")]');
$d->find_element('//*[@id="rewrite_rule_set.1"]')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check if correct ruleset has been selected');
$d->find_element('Number Manipulations', 'link_text')->click;
ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td[4]/select/option[@selected="selected"]', $rulesetname), 'rewrite_rule_set value has been set');

diag("Open delete dialog and press cancel");
$c->delete_rw_ruleset($rulesetname, 1);
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset is still here');

diag('Open delete dialog and press delete');
$c->delete_rw_ruleset($rulesetname, 0);
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Ruleset was deleted');

$c->delete_domain($domainstring);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        is("tests", "failed", "This test wasnt successful, check complete test logs for more info");
        diag("-----------------------SCRIPT HAS CRASHED-----------------------");
        if($d->find_text("Sorry!") || $d->find_text("Oops!")) {
            my $incident;
            my $time;
            my $crashvar = $d->find_element_by_css('.error-container > h2:nth-child(2)')->get_text();
            eval {
                $incident = $d->find_element('.error-details > div:nth-child(2)', 'css')->get_text();
                $time = $d->find_element('.error-details > div:nth-child(3)', 'css')->get_text();
            };
            my $realtime = localtime();
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Server error: $crashvar");
            diag($incident);
            diag($time);
            diag("Perl localtime(): $realtime");
        } elsif($d->find_text("nginx")) {
            my $crashvar = $d->find_element_by_css('body > center:nth-child(1) > h1:nth-child(1)')->get_text();
            my $realtime = localtime();
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("nginx error: $crashvar");
            diag("Perl localtime(): $realtime");
        } else {
            diag("Could not detect Server issues. Maybe script problems?");
            diag("If you still want to check server logs, here's some info");
            my $realtime = localtime();
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Perl localtime(): $realtime");
        }
        diag("----------------------------------------------------------------");
    };
    done_testing;
}
