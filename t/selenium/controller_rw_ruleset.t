use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;

sub ctr_rw_ruleset {
    my ($port) = @_;
    $port = '6666' unless $port;

    my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

    my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
        browser_name => $browsername,
        extra_capabilities => {
            acceptInsecureCerts => \1,
        },
        port => $port
    );

    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $resellername = ("reseller" . int(rand(100000)) . "test");
    my $contractid = ("contract" . int(rand(100000)) . "test");
    my $rulesetname = ("rule" . int(rand(100000)) . "test");
    my $domainstring = ("domain" . int(rand(100000)) . ".example.org");

    $c->login_ok();
    $c->create_reseller_contract($contractid);
    $c->create_reseller($resellername, $contractid);
    $c->create_rw_ruleset($rulesetname, $resellername);

    diag('Search for our new Rewrite Rule Set');
    $d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset was found');

    diag('Create a new Rule for Caller');
    $d->move_action(element => $d->find_element('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Rules")]'));
    $d->find_element('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]//td//div//a[contains(text(), "Rules")]')->click();
    $d->find_element('Create Rewrite Rule', 'link_text')->click;
    $d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
    $d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\2');
    $d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
    $d->find_element('//*[@id="field.1"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if Rule has been created');
    $d->find_element('Inbound Rewrite Rules for Caller', 'link_text')->click();
    ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="collapse_icaller"]/div/table/tbody/tr[1]//td[contains(text(), "International to E.164")]'), "Description is correct");

    diag('Create a new Rule for Callee');
    $d->find_element('Create Rewrite Rule', 'link_text')->click;
    $d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
    $d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\2');
    $d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
    $d->find_element('//*[@id="field.0"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if Rule has been created');
    $d->find_element('Inbound Rewrite Rules for Callee', 'link_text')->click();
    ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "^(00|\+)([1-9][0-9]+)$")]'), "Match Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "\2")]'), "Replacement Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="collapse_icallee"]/div/table/tbody/tr[1]//td[contains(text(), "International to E.164")]'), "Description is correct");

    diag('Testing if rules can be reordered');
    diag('Create a new rule for Caller');
    $d->find_element('Create Rewrite Rule', 'link_text')->click;
    $d->fill_element('//*[@id="match_pattern"]', 'xpath', '^(00|\+)([1-9][0-9]+)$');
    $d->fill_element('//*[@id="replace_pattern"]', 'xpath', '\1');
    $d->fill_element('//*[@id="description"]', 'xpath', 'International to E.164');
    $d->find_element('//*[@id="field.1"]')->click();
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
    $d->move_action(element => $d->find_element('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Preferences")]'));
    $d->find_element('//*[@id="Domain_table"]/tbody/tr[1]//td//div//a[contains(text(),"Preferences")]')->click();

    diag('Add ruleset to a domain');
    $d->find_element('Number Manipulations', 'link_text')->click;
    $d->move_action(element => $d->find_element('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td/div//a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td/div//a[contains(text(), "Edit")]')->click();
    $d->find_element('//*[@id="rewrite_rule_set.1"]')->click();
    $d->find_element('//*[@id="save"]')->click();

    diag('Check if correct ruleset has been selected');
    $d->find_element('Number Manipulations', 'link_text')->click;

    ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "rewrite_rule_set")]/../td[4]/select/option[@selected="selected"]', $rulesetname), 'rewrite_rule_set value has been set');

    diag("Open delete dialog and press cancel");
    $c->delete_rw_ruleset($rulesetname, 1);
    $d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset is still here');

    diag('Open delete dialog and press delete');
    $c->delete_rw_ruleset($rulesetname, 0);
    $d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
    ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Ruleset was deleted');

    $c->delete_domain($domainstring);
    $c->delete_reseller_contract($contractid);
    $c->delete_reseller($resellername);
}

if(! caller) {
    ctr_rw_ruleset();
    done_testing;
}

1;