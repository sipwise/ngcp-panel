use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

sub ctr_ncos {
    my ($port) = @_;
    my $d = Selenium::Collection::Functions::create_driver($port);
    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $resellername = ("reseller" . int(rand(100000)) . "test");
    my $contractid = ("contract" . int(rand(100000)) . "test");
    my $ncosname = ("ncos" . int(rand(100000)) . "level");

    $c->login_ok();
    $c->create_reseller_contract($contractid);
    $c->create_reseller($resellername, $contractid);

    diag('Go to NCOS interface');
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("NCOS Levels", 'link_text')->click();

    diag('Trying to create a new administrator');
    $d->find_element("Create NCOS Level", 'link_text')->click();

    diag('Fill in values');
    $d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
    ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
    $d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
    $d->fill_element('//*[@id="level"]', 'xpath', $ncosname);
    $d->find_element('//*[@id="mode"]/option[@value="blacklist"]')->click();
    $d->fill_element('//*[@id="description"]', 'xpath', "This is a simple description");
    $d->find_element('//*[@id="save"]')->click();

    diag('Search for our new NCOS');
    $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);

    diag("Check NCOS details");
    ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]/tbody/tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
    ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]/tbody/tr[1]/td[contains(text(), ' . $ncosname . ')]'), 'NCOS name is correct');
    ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]/tbody/tr[1]/td[contains(text(), "blacklist")]'), "NCOS mode is correct");
    ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]/tbody/tr[1]/td[contains(text(), "This is a simple description")]'), "NCOS descriptions is correct");

    diag("Enter NCOS patterns");
    $d->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Patterns")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');

    diag("Create new pattern");
    $d->find_element("Create Pattern Entry", 'link_text')->click();

    diag("Enter pattern details");
    $d->fill_element('//*[@id="pattern"]', 'xpath', '^439');
    $d->fill_element('//*[@id="description"]', 'xpath', 'Austrian Premium Numbers');
    $d->find_element('//*[@id="save"]')->click();

    diag("Check pattern details");
    ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "^439")]'), "Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "Austrian Premium Numbers")]'), "Description is correct");

    diag("Create LNP entry");
    $d->find_element("Create LNP Entry", 'link_text')->click();

    diag("Enter LNP details");
    $d->select_if_unselected('//*[@id="lnp_provideridtable"]/tbody/tr[1]/td[4]/input');
    $d->fill_element('//*[@id="description"]', 'xpath', 'Rule for LNP Carrier 1');
    $d->find_element('//*[@id="save"]')->click();

    diag("Check LNP details");
    ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]/tbody/tr/td[contains(text(), "Rule for LNP Carrier 1")]'), "Description is correct");

    diag("Edit NCOS settings");
    $d->find_element('//*[@id="number_patterns_extra"]/div[2]/a')->click();
    $d->select_if_unselected('//*[@id="local_ac"]');
    $d->find_element('//*[@id="save"]')->click();

    diag("Check if NCOS settings have been applied");
    ok($d->find_element_by_xpath('//*[@id="local_ac"][@checked="checked"]'), 'Setting "Include local area code" was applied');

    diag("Go back to NCOS page");
    $d->find_element("Back", 'link_text')->click();

    diag("Trying to delete NCOS");
    $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
    ok($d->wait_for_text('//*[@id="ncos_level_table"]/tbody/tr[1]/td[3]', $ncosname), "NCOS found");
    $d->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');
    $d->find_element('//*[@id="dataConfirmOK"]')->click();

    $c->delete_reseller_contract($contractid);
    $c->delete_reseller($resellername);

}

if(! caller) {
    ctr_ncos();
    done_testing;
}

1;