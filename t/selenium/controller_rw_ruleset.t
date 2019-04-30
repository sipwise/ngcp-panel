use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
);

my $c = Selenium::Collection::Common->new(
    driver => $d
);

$c->login_ok();

my $resellername = ("test" . int(rand(10000)));
my $contractid = ("test" . int(rand(10000)));
my $rulesetname = ("rule" . int(rand(10000)));

$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

$c->create_rw_ruleset($resellername, $rulesetname);

diag('Search for our new Rewrite Rule Set');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#rewrite_rule_set_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="rewrite_rule_set_table_filter"]/label/input', 'xpath', $rulesetname);
ok($d->wait_for_text('//*[@id="rewrite_rule_set_table"]/tbody/tr[1]/td[3]', $rulesetname), 'Ruleset was found');

diag('Create a new Rule');
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

$c->delete_rw_ruleset($rulesetname);

$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

done_testing;