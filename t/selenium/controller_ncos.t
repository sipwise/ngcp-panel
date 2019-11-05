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
$c->create_ncos($resellername, $ncosname);

diag("Go to 'Number Porting' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Number Porting', 'link_text')->click();

diag("Try to create an empty LNP Carrier");
$d->find_element('Create LNP Carrier', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Prefix field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="name"]', 'xpath', $lnpcarrier);
$d->fill_element('//*[@id="prefix"]', 'xpath', $prefix);
$d->find_element('//*[@id="save"]')->click();

diag("Search LNP Carrier");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'LNP carrier successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "' . $lnpcarrier . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "' . $prefix . '")]'), 'Prefix is correct');

diag("Edit LNP Carrier");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$lnpcarrier = ("lnp" . int(rand(100000)) . "carrier");
$prefix = ("prefix" . int(rand(100000)) . "stuff");
$d->fill_element('//*[@id="name"]', 'xpath', $lnpcarrier);
$d->fill_element('//*[@id="prefix"]', 'xpath', $prefix);
$d->find_element('//*[@id="save"]')->click();

diag("Search LNP Carrier");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'LNP carrier successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);

diag("Check details");
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "' . $lnpcarrier . '")]'), 'Name is correct');
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "' . $prefix . '")]'), 'Prefix is correct');

diag("Go to 'NCOS Levels' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("NCOS Levels", 'link_text')->click();

diag("Trying to create a empty NCOS Level");
$d->find_element("Create NCOS Level", 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->find_element('//*[@id="save"]')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Level Name field is required")]'));
$d->find_element('//*[@id="mod_close"]')->click();

diag("Search our new NCOS");
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);

diag("Check NCOS details");
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), ' . $ncosname . ')]'), 'NCOS name is correct');
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), "blacklist")]'), 'NCOS mode is correct');
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), "This is a simple description")]'), 'NCOS description is correct');

diag("Edit NCOS");
$d->move_and_click('//*[@id="ncos_level_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="ncos_level_table_filter"]//input');
$ncosname = ("ncos" . int(rand(100000)) . "level");
$d->fill_element('//*[@id="level"]', 'xpath', $ncosname);
$d->find_element('//*[@id="mode"]/option[@value="whitelist"]')->click();
$d->fill_element('//*[@id="description"]', 'xpath', 'This is a very simple description');
$d->find_element('//*[@id="save"]')->click();

diag("Search NCOS");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS level successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);

diag("Check NCOS details");
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), ' . $ncosname . ')]'), 'NCOS name is correct');
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), "whitelist")]'), "NCOS mode is correct");
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), "This is a very simple description")]'), 'NCOS description is correct');

diag("Enter NCOS Patterns");
$d->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Patterns")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');
ok($d->find_element_by_xpath('//*[@id="masthead"]//div//h2[contains(text(), "NCOS details")]'), "We are on the correct page");
sleep 1;

diag("Create a new Pattern");
$d->find_element('Create Pattern Entry', 'link_text')->click();

diag("Save Pattern");
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Pattern field is required")]'));

diag("Enter Pattern details");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Create Number Pattern")]'), "Edit Window has been opened");
$d->fill_element('//*[@id="pattern"]', 'xpath', '^439');
$d->fill_element('//*[@id="description"]', 'xpath', 'Austrian Premium Numbers');
$d->find_element('//*[@id="save"]')->click();

diag("Check Pattern details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS pattern successfully created',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]//tr[1]/td[contains(text(), "^439")]'), 'Pattern is correct');
ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]//tr[1]/td[contains(text(), "Austrian Premium Numbers")]'), 'Description is correct');

diag("Edit NCOS Pattern");
$d->move_and_click('//*[@id="number_pattern_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="number_pattern_table_filter"]//input');
$d->fill_element('//*[@id="pattern"]', 'xpath', '^491');
$d->fill_element('//*[@id="description"]', 'xpath', 'German Premium Numbers');
$d->find_element('//*[@id="save"]')->click();

diag("Check Pattern details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS pattern successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]//tr[1]/td[contains(text(), "^491")]'), 'Pattern is correct');
ok($d->find_element_by_xpath('//*[@id="number_pattern_table"]//tr[1]/td[contains(text(), "German Premium Numbers")]'), 'Description is correct');

diag("Create LNP entry");
$d->find_element("Create LNP Entry", 'link_text')->click();

diag("Enter LNP details");
$d->fill_element('//*[@id="lnp_provideridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_provideridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_provideridtable_filter"]/label/input', 'xpath', $lnpcarrier);
ok($d->find_element_by_xpath('//*[@id="lnp_provideridtable"]//tr[1]/td[contains(text(), "' . $lnpcarrier . '")]'), 'LNP Carrier was found');
$d->select_if_unselected('//*[@id="lnp_provideridtable"]/tbody/tr[1]/td[4]/input[@type="checkbox"]');
$d->fill_element('//*[@id="description"]', 'xpath', 'Rule for LNP Carrier 1');
$d->find_element('//*[@id="save"]')->click();

diag("Check LNP details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS lnp entry successfully created',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "' . $lnpcarrier . '")]'), 'LNP Carrier is correct');
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "Rule for LNP Carrier 1")]'), 'Description is correct');

diag("Edit LNP entry");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$d->fill_element('//*[@id="description"]', 'xpath', 'Rule for LNP Carrier 2');
$d->find_element('//*[@id="save"]')->click();

diag("Check LNP details");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS lnp entry successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "' . $lnpcarrier . '")]'), 'LNP Carrier is correct');
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "Rule for LNP Carrier 2")]'), 'Description is correct');

diag("Edit NCOS settings");
$d->find_element('//*[@id="number_patterns_extra"]//div//a')->click();
$d->select_if_unselected('//*[@id="local_ac"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check if NCOS settings have been applied");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS level setting successfully updated',  'Correct Alert was shown');
ok($d->find_element_by_xpath('//*[@id="local_ac"][@checked="checked"]'), 'Setting "Include local area code" was applied');

diag("Creating Domain to add NCOS Level");
$c->create_domain($domainstring, $resellername);

diag("Searching Domain");
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->find_element_by_xpath('//*[@id="Domain_table"]//tr[1]/td[contains(text(), "' . $domainstring . '")]'), 'Domain was found');
$d->move_and_click('//*[@id="Domain_table"]//tr[1]//td//a[contains(text(), "Preferences")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');

diag("Open 'Call Blockings'");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element('//*[@id="preference_groups"]//div//a[contains(text(),"Call Blockings")]'));

diag("Edit setting 'NCOS'");
$d->move_and_click('//table//tr//td[contains(text(), "ncos")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr//td[contains(text(), "adm_cf_ncos")]/../td//a[contains(text(), "Edit")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), 'Edit Window has been opened');
$d->move_and_click('//*[@id="ncos"]', 'xpath', '//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]');
$d->find_element('//*[@id="ncos"]/option[contains(text(), "' . $ncosname . '")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if NCOS Level was applied");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Preference ncos successfully updated',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "ncos")]/../td/select/option[contains(text(), "' . $ncosname . '")][@selected="selected"]'), 'NCOS Level was applied');

diag("Go back to NCOS interface");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("NCOS Levels", 'link_text')->click();

diag("Search our new NCOS");
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), "' . $ncosname . '")]'), 'NCOS was found');

diag("Go to 'NCOS Patterns' page");
$d->move_and_click('//*[@id="ncos_level_table"]/tbody/tr[1]/td/div/a[contains(text(), "Patterns")]', 'xpath', '//*[@id="ncos_level_table_filter"]/label/input');

diag("Delete NCOS Number pattern");
$d->move_and_click('//*[@id="number_pattern_table"]//tr//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="number_pattern_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if NCOS Number pattern has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS pattern successfully deleted',  'Correct Alert was shown');
ok($d->find_element_by_css('#number_pattern_table tr > td.dataTables_empty', 'css'), 'NCOS Number pattern has been deleted');

diag("Delete LNP Entry");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if LNP Entry has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'NCOS lnp entry successfully deleted',  'Correct Alert was shown');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'LNP Entry has been deleted');

diag("Try to NOT delete NCOS");
$c->delete_ncos($ncosname, 1);

diag("Check if NCOS is still here");
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
ok($d->find_element_by_xpath('//*[@id="ncos_level_table"]//tr[1]/td[contains(text(), "' . $ncosname . '")]'), 'NCOS still here');

diag("Try to delete NCOS");
$c->delete_ncos($ncosname);

diag("Check if NCOS has been deleted");
$d->fill_element('//*[@id="ncos_level_table_filter"]/label/input', 'xpath', $ncosname);
ok($d->find_element_by_css('#ncos_level_table tr > td.dataTables_empty', 'css'), 'NCOS has been deleted');

diag("Go to 'Number Porting' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Number Porting", 'link_text')->click();

diag("Try to NOT delete LNP Carrier");
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "' . $lnpcarrier . '")]'), 'LNP Carrier found');
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if LNP Carrier is still here");
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);
ok($d->find_element_by_xpath('//*[@id="lnp_carriers_table"]//tr[1]/td[contains(text(), "' . $lnpcarrier . '")]'), 'LNP Carrier is still here');

diag("Try to delete LNP Carrier");
$d->move_and_click('//*[@id="lnp_carriers_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="lnp_carriers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if LNP Carrier has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "LNP carrier successfully deleted",  'Correct Alert was shown');
$d->fill_element('//*[@id="lnp_carriers_table_filter"]/label/input', 'xpath', $lnpcarrier);
$d->move_and_click('//*[@id="lnp_numbers_table_filter"]//label//input', 'xpath', '//*[@id="content"]/div/h3[contains(text(), "LNP Numbers")]');
ok($d->find_element_by_css('#lnp_carriers_table tr > td.dataTables_empty', 'css'), 'LNP Carrier has been deleted');
$d->find_element('//*[@id="content"]//div//a[contains(text(), "Back")]')->click();

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