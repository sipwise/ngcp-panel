use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;
use TryCatch;

my ($port) = @_;
my $d = Selenium::Collection::Functions::create_driver($port);
my $c = Selenium::Collection::Common->new(
    driver => $d
);

my $resellername = ("reseller" . int(rand(100000)) . "test");
my $contractid = ("contract" . int(rand(100000)) . "test");
my $ncosname = ("ncos" . int(rand(100000)) . "level");
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $lnpcarrier = ("lnp" . int(rand(100000)) . "carrier");
my $prefix = ("prefix" . int(rand(100000)) . "stuff");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag("Go to Number Porting Page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Number Porting", 'link_text')->click();

diag("Trying to create a empty LNP Carrier");
$d->find_element("Create LNP Carrier", 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Prefix field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="name"]', 'xpath', $lnpcarrier);
$d->fill_element('//*[@id="prefix"]', 'xpath', $prefix);
$d->find_element('//*[@id="save"]')->click();

diag("Search for LNP carrier");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "LNP carrier successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);

diag("Check details");
ok($d->wait_for_text('//*[@id="lnp_carriers_table"]/tbody/tr[1]/td[2]', $lnpcarrier), "Name is correct");
ok($d->wait_for_text('//*[@id="lnp_carriers_table"]/tbody/tr[1]/td[3]', $prefix), "Prefix is correct");

diag("Edit LNP Carrier");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$lnpcarrier = ("lnp" . int(rand(100000)) . "carrier");
$prefix = ("prefix" . int(rand(100000)) . "stuff");
$d->fill_element('//*[@id="name"]', 'xpath', $lnpcarrier);
$d->fill_element('//*[@id="prefix"]', 'xpath', $prefix);
$d->find_element('//*[@id="save"]')->click();

diag("Search for LNP carrier");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "LNP carrier successfully updated",  "Correct Alert was shown");
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);

diag("Check details");
ok($d->wait_for_text('//*[@id="lnp_carriers_table"]/tbody/tr[1]/td[2]', $lnpcarrier), "Name is correct");
ok($d->wait_for_text('//*[@id="lnp_carriers_table"]/tbody/tr[1]/td[3]', $prefix), "Prefix is correct");

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
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS level successfully created",  "Correct Alert was shown");
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
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS level successfully updated",  "Correct Alert was shown");
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
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "NCOS details")]'), "We are on the correct Page");
sleep 1;

diag("Create new pattern");
$d->find_element("Create Pattern Entry", 'link_text')->click();

diag("Click 'Save'");
$d->find_element('//*[@id="save"]')->click();

diag("Check Error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Pattern field is required")]'));

diag("Enter pattern details");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Number Pattern")]'), "Edit Window has been opened");
$d->fill_element('//*[@id="pattern"]', 'xpath', '^439');
$d->fill_element('//*[@id="description"]', 'xpath', 'Austrian Premium Numbers');
$d->find_element('//*[@id="save"]')->click();

diag("Check pattern details");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS pattern successfully created",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "^439")]'), "Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "Austrian Premium Numbers")]'), "Description is correct");

diag("Edit NCOS Pattern");
$d->move_and_click('//*[@id="number_pattern_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="number_pattern_table_filter"]//input');
$d->fill_element('//*[@id="pattern"]', 'xpath', '^491');
$d->fill_element('//*[@id="description"]', 'xpath', 'German Premium Numbers');
$d->find_element('//*[@id="save"]')->click();

diag("Check pattern details");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS pattern successfully updated",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "^491")]'), "Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]/tbody/tr/td[contains(text(), "German Premium Numbers")]'), "Description is correct");

diag("Create LNP entry");
$d->find_element("Create LNP Entry", 'link_text')->click();

diag("Enter LNP details");
$d->fill_element('//*[@id="lnp_provideridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_provideridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_provideridtable_filter"]/label/input', 'xpath', $lnpcarrier);
ok($d->wait_for_text('//*[@id="lnp_provideridtable"]/tbody/tr[1]/td[2]', $lnpcarrier), "Name is correct");
$d->select_if_unselected('//*[@id="lnp_provideridtable"]/tbody/tr[1]/td[4]/input[@type="checkbox"]');
$d->fill_element('//*[@id="description"]', 'xpath', 'Rule for LNP Carrier 1');
$d->find_element('//*[@id="save"]')->click();

diag("Check LNP details");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS lnp entry successfully created",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]/tbody/tr/td[contains(text(), "' . $lnpcarrier . '")]'), "LNP Carrier is correct");
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]/tbody/tr/td[contains(text(), "Rule for LNP Carrier 1")]'), "Description is correct");

diag("Edit LNP entry");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$d->fill_element('//*[@id="description"]', 'xpath', 'Rule for LNP Carrier 2');
$d->find_element('//*[@id="save"]')->click();

diag("Check LNP details");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS lnp entry successfully updated",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]/tbody/tr/td[contains(text(), "' . $lnpcarrier . '")]'), "LNP Carrier is correct");
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]/tbody/tr/td[contains(text(), "Rule for LNP Carrier 2")]'), "Description is correct");

diag("Edit NCOS settings");
$d->find_element('//*[@id="number_patterns_extra"]//div//a')->click();
$d->select_if_unselected('//*[@id="local_ac"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check if NCOS settings have been applied");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS level setting successfully updated",  "Correct Alert was shown");
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
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");
ok($d->find_element_by_xpath('//*[@id="ncos"]/option[contains(text(), "' . $ncosname . '")]'), "Element was found");
$d->find_element('//*[@id="ncos"]/option[contains(text(), "' . $ncosname . '")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if NCOS Level was applied");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "Preference ncos successfully updated",  "Correct Alert was shown");
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
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS pattern successfully deleted",  "Correct Alert was shown");
ok($d->find_element_by_css('#number_pattern_table tr > td.dataTables_empty', 'css'), 'NCOS Number pattern was deleted');

diag("Delete LNP Entry");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if LNP Entry was deleted");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS lnp entry successfully deleted",  "Correct Alert was shown");
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'LNP Entry was deleted');

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
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "NCOS level successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'NCOS was deleted');

diag("Go to Number Porting Page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Number Porting", 'link_text')->click();

diag("Trying to NOT delete LNP carrier");
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);
ok($d->wait_for_text('//*[@id="lnp_carriers_table"]/tbody/tr[1]/td[2]', $lnpcarrier), "Name is correct");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Entry is still here");
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);
ok($d->wait_for_text('//*[@id="lnp_carriers_table"]/tbody/tr[1]/td[2]', $lnpcarrier), "Entry is still here");

diag("Trying to delete LNP carrier");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Entry was deleted");
is($d->find_element_by_xpath('//*[@id="content"]//div[contains(@class, "alert")]')->get_text(), "LNP carrier successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);
$d->move_and_click('//*[@id="lnp_numbers_table_filter"]//label//input', 'xpath', '//*[@id="content"]/div/h3[contains(text(), "LNP Numbers")]');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Entry was deleted');

$c->delete_domain($domainstring);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_ncos.png");
    }
    $d->quit();
    done_testing;
}