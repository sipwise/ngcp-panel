use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;
use TryCatch;

sub ctr_ncos {
    my ($port) = @_;
    my $d = Selenium::Collection::Functions::create_driver($port);
    my $c = Selenium::Collection::Common->new(
        driver => $d
    );

    my $resellername = ("reseller" . int(rand(100000)) . "test");
    my $contractid = ("contract" . int(rand(100000)) . "test");
    my $ncosname = ("ncos" . int(rand(100000)) . "level");
    my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
    try {
        $c->login_ok();
        $c->create_reseller_contract($contractid);
        $c->create_reseller($resellername, $contractid);

        diag('Go to NCOS interface');
        $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
        $d->find_element("NCOS Levels", 'link_text')->click();

        diag('Trying to create a empty NCOS Level');
        $d->find_element("Create NCOS Level", 'link_text')->click();
        $d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
        $d->find_element('//*[@id="save"]')->click();

        diag('Check Error Messages');
        ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
        ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Level Name field is required")]'));

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

        diag('Edit NCOS');
        $d->move_and_click('//*[@id="ncos_level_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="ncos_level_table_filter"]//input');
        $ncosname = ("ncos" . int(rand(100000)) . "level");
        $d->fill_element('//*[@id="level"]', 'xpath', $ncosname);
        $d->find_element('//*[@id="mode"]/option[@value="whitelist"]')->click();
        $d->fill_element('//*[@id="description"]', 'xpath', "This is a very simple description");
        $d->find_element('//*[@id="save"]')->click();

        diag('Search for NCOS');
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
        ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);

        diag("Check NCOS details");
        ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]/tbody/tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
        ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]/tbody/tr[1]/td[contains(text(), ' . $ncosname . ')]'), 'NCOS name is correct');
        ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]/tbody/tr[1]/td[contains(text(), "whitelist")]'), "NCOS mode is correct");
        ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]/tbody/tr[1]/td[contains(text(), "This is a very simple description")]'), "NCOS descriptions is correct");

        diag("Enter NCOS patterns");
        $d->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Patterns")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');

        diag("Create new pattern");
        $d->find_element("Create Pattern Entry", 'link_text')->click();

        diag("Click 'Save'");
        $d->find_element('//*[@id="save"]')->click();

        diag("Check Error messages");
        ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Pattern field is required")]'));

        diag("Enter pattern details");
        $d->fill_element('//*[@id="pattern"]', 'xpath', '^439');
        $d->fill_element('//*[@id="description"]', 'xpath', 'Austrian Premium Numbers');
        $d->find_element('//*[@id="save"]')->click();

        diag("Check pattern details");
        ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "^439")]'), "Pattern is correct");
        ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "Austrian Premium Numbers")]'), "Description is correct");

        diag("Edit NCOS Pattern");
        $d->move_and_click('//*[@id="number_pattern_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="number_pattern_table_filter"]//input');
        $d->fill_element('//*[@id="pattern"]', 'xpath', '^491');
        $d->fill_element('//*[@id="description"]', 'xpath', 'German Premium Numbers');
        $d->find_element('//*[@id="save"]')->click();

        diag("Check pattern details");
        ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "^491")]'), "Pattern is correct");
        ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "German Premium Numbers")]'), "Description is correct");
=pod
        diag("Create LNP entry");
        $d->find_element("Create LNP Entry", 'link_text')->click();

        diag("Enter LNP details");
        $d->select_if_unselected('//*[@id="lnp_provideridtable"]/tbody/tr[1]/td[4]/input[@type="checkbox"]');
        $d->fill_element('//*[@id="description"]', 'xpath', 'Rule for LNP Carrier 1');
        $d->find_element('//*[@id="save"]')->click();

        diag("Check LNP details");
        ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]/tbody/tr/td[contains(text(), "Rule for LNP Carrier 1")]'), "Description is correct");
=cut
        diag("Edit NCOS settings");
        $d->find_element('//*[@id="number_patterns_extra"]/div[2]/a')->click();
        $d->select_if_unselected('//*[@id="local_ac"]');
        $d->find_element('//*[@id="save"]')->click();

        diag("Check if NCOS settings have been applied");
        ok($d->find_element_by_xpath('//*[@id="local_ac"][@checked="checked"]'), 'Setting "Include local area code" was applied');

        diag("Creating Domain to add NCOS Level");
        $c->create_domain($domainstring, $resellername);

        diag("Searching Domain");
        $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
        ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
        $d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
        ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[contains(text(), "domain")]', $domainstring), "Domain was found");
        $d->move_and_click('//*[@id="Domain_table"]//tr[1]//td//a[contains(text(), "Preferences")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');

        diag("Open 'Call Blockings'");
        $d->find_element("Call Blockings", 'link_text')->click();
        $d->scroll_to_element($d->find_element('//*[@id="preference_groups"]//div//a[contains(text(),"Call Blockings")]'));

        diag("Edit setting 'NCOS'");
        $d->move_and_click('//table//tr//td[contains(text(), "ncos")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(),"Call Blockings")]');
        $d->find_element('//*[@id="ncos"]/option[contains(text(), "' . $ncosname . '")]')->click();
        $d->find_element('//*[@id="save"]')->click();

        diag("Check if NCOS Level was applied");
        ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "ncos")]/../td/select/option[contains(text(), "' . $ncosname . '")][@selected="selected"]'), 'NCOS Level was applied');

        diag('Go back to NCOS interface');
        $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
        $d->find_element("NCOS Levels", 'link_text')->click();

        diag('Search for our new NCOS');
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
        ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
        ok($d->wait_for_text('//*[@id="ncos_level_table"]/tbody/tr[1]/td[3]', $ncosname), 'NCOS was found');

        diag('Go to NCOS settings');
        $d->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Patterns")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');

        diag("Delete NCOS Number pattern");
        $d->move_and_click('//*[@id="number_pattern_table"]//tr//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="number_pattern_table_filter"]/label/input');
        $d->find_element('//*[@id="dataConfirmOK"]')->click();

        diag("Check if NCOS Number pattern was deleted");
        ok($d->find_element_by_css('#number_pattern_table tr > td.dataTables_empty', 'css'), 'NCOS Number pattern was deleted');
=pod
        diag("Delete LNP carrier");
        $d->move_and_click('//*[@id="lnp_carriers_table"]//tr//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
        $d->find_element('//*[@id="dataConfirmOK"]')->click();

        diag("Check if LNP carrier was deleted");
        ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'NCOS Number pattern was deleted');
=cut
        diag("Go back to NCOS page");
        $d->find_element("Back", 'link_text')->click();

        diag("Trying to NOT delete NCOS");
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
        ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
        ok($d->wait_for_text('//*[@id="ncos_level_table"]/tbody/tr[1]/td[3]', $ncosname), "NCOS found");
        $d->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');
        $d->find_element('//*[@id="dataConfirmCancel"]')->click();

        diag("Check if Entry is still here");
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
        ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
        ok($d->wait_for_text('//*[@id="ncos_level_table"]/tbody/tr[1]/td[3]', $ncosname), "NCOS still here");

        diag("Trying to delete NCOS");
        $d->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');
        $d->find_element('//*[@id="dataConfirmOK"]')->click();

        diag("Check if Entry was deleted");
        $d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
        ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'NCOS was deleted');


        $c->delete_domain($domainstring);
        $c->delete_reseller_contract($contractid);
        $c->delete_reseller($resellername);
    } catch {
        is("tests", "failed", "This test wasnt successful, check complete test logs for more info");
        diag("-----------------------SCRIPT HAS CRASHED-----------------------");
        if($d->find_text("Sorry!")) {
            my $crashvar = $d->find_element_by_css('.error-container > h2:nth-child(2)')->get_text();
            my $incident = $d->find_element_by_css('.error-details > div:nth-child(2)')->get_text();
            my $time = $d->find_element_by_css('.error-details > div:nth-child(3)')->get_text();
            my $realtime = localtime();
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Server error: $crashvar");
            diag($incident);
            diag($time);
            diag("Perl localtime(): $realtime");
        } else {
            diag("Could not detect Server issues. Maybe script problems?");
            diag("If you still want to check server logs, here's some info");
            my $realtime = localtime();
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Perl localtime(): $realtime");
        }
        diag("----------------------------------------------------------------");
    }
}

if(! caller) {
    ctr_ncos();
    done_testing;
}

1;