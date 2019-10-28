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
my $containername = ("emergency" . int(rand(100000)) . "container");
my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $run_ok = 0;

$c->login_ok();
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag("Go to 'Emergency Mappings' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Emergency Mappings', 'link_text')->click();

diag("Try to create an empty Emergency Container");
$d->find_element('Create Emergency Container', 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]//td//input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->find_element_by_xpath('//*[@id="reselleridtable"]//tr[1]/td[contains(text(), "' . $resellername . '")]'), 'Reseller found');
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $containername);
$d->find_element('//*[@id="save"]')->click();

diag("Search Emergency Container");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Emergency mapping container successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);

diag("Check Emergency Container details");
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]//tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]//tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container name is correct');

diag("Edit Emergency Container name");
$containername = ("emergency" . int(rand(100000)) . "container");
$d->move_and_click('//*[@id="emergency_containers_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="emergency_containers_table_filter"]//input');
$d->fill_element('//*[@id="name"]', 'xpath', $containername);
$d->find_element('//*[@id="save"]')->click();

diag("Search Emergency Container");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Emergency mapping container successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);

diag("Check Emergency Container details");
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]//tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]//tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container name is correct');

diag("Try to create a empty Emergency Mapping");
$d->find_element('Create Emergency Mapping', 'link_text')->click();
$d->unselect_if_selected('//*[@id="emergency_containeridtable"]//tr[1]//td//input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Emergency Mapping Container field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Code field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="emergency_containeridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containeridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containeridtable_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_xpath('//*[@id="emergency_containeridtable"]//tr[1]/td[contains(text(), "' . $containername . '")]'), 'Emergency Container found');
$d->select_if_unselected('//*[@id="emergency_containeridtable"]/tbody/tr[1]/td[4]/input', 'xpath');
$d->fill_element('//*[@id="code"]', 'xpath', "133");
$d->fill_element('//*[@id="prefix"]', 'xpath', "E1_133_");
$d->find_element('//*[@id="save"]')->click();

diag("Search Emergency Mapping");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Emergency mapping successfully created',  'Correct Alert was shown');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);

diag("Check Emergency Mapping details");
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container name is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), "133")]'), 'Emergency Number is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), "E1_133_")]'), 'Emergency Prefix is correct');

diag("Edit Emergency Mapping Details");
$d->move_and_click('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[6]/div/a[2]', 'xpath', '//*[@id="emergency_mappings_table_filter"]//input');
$d->fill_element('//*[@id="code"]', 'xpath', "144");
$d->fill_element('//*[@id="prefix"]', 'xpath', "E2_144_");
$d->find_element('//*[@id="save"]')->click();

diag("Search Emergency Mapping");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Emergency mapping successfully updated',  'Correct Alert was shown');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);

diag("Check Emergency Mapping details");
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container name is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), "144")]'), 'Emergency Number is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), "E2_144_")]'), 'Emergency Prefix is correct');

diag("Create Domain to add Emergency Container");
$c->create_domain($domainstring, $resellername);

diag("Search Domain");
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->find_element_by_xpath('//*[@id="Domain_table"]//tr[1]/td[contains(text(), "' . $domainstring . '")]'), 'Domain was found');
$d->move_and_click('//*[@id="Domain_table"]//tr[1]//td//a[contains(text(), "Preferences")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');

diag("Open 'Number Manipulations'");
$d->find_element('//*[@id="toggle-accordions"]')->click();

diag("Edit setting 'emergency_mapping_container'");
$d->scroll_to_element($d->find_element('//table//tr//td[contains(text(), "emergency_mapping_container")]'));
$d->move_and_click('//table//tr//td[contains(text(), "emergency_mapping_container")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "NAT and Media Flow Control")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");
$d->find_element('//*[@id="emergency_mapping_container"]/option[contains(text(), "' . $containername . '")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if setting 'emergency_mapping_container' was applied");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Preference emergency_mapping_container successfully updated',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "emergency_mapping_container")]/../td/select/option[contains(text(), "' . $containername . '")][@selected="selected"]'), 'NCOS Level was applied');

diag("Edit setting 'emergency_mode_enabled'");
$d->scroll_to_element($d->find_element('//table//tr//td[contains(text(), "emergency_mode_enabled")]'));
$d->move_and_click('//table//tr//td[contains(text(), "emergency_mode_enabled")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr//td[contains(text(), "call_deflection")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), 'Edit Window has been opened');
$d->select_if_unselected('//*[@id="emergency_mode_enabled"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check if setting 'emergency_mode_enabled' was enabled");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Preference emergency_mode_enabled successfully updated',  'Correct Alert was shown');
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "emergency_mode_enabled")]/../td//input[@checked="checked"]'), 'Setting was enabled');

diag("Go to 'Emergency Mappings' page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('Emergency Mappings', 'link_text')->click();

diag("Try to NOT delete Emergency Mapping");
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[2][contains(text(), "' . $containername . '")]'), 'Emergency mapping was found');
$d->move_and_click('//*[@id="emergency_mappings_table"]/tbody/tr/td[6]/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="emergency_mappings_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Emergency Mapping is still here");
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]//tr[1]/td[contains(text(), ' . $containername . ')]'), 'Mapping is still here');

diag("Try to delete Emergency Mapping");
$d->move_and_click('//*[@id="emergency_mappings_table"]/tbody/tr/td[6]/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="emergency_mappings_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Emergency Mapping has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Emergency mapping successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Emergency Mapping has been deleted');

diag("Try to NOT delete Emergency Container");
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]//tr[1]/td[3][contains(text(), "' . $containername . '")]'), 'Emergency mapping was found');
$d->move_and_click('//*[@id="emergency_containers_table"]/tbody/tr/td[4]/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="emergency_containers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Emergency Container is still here");
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]//tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container is still here');

diag("Try to delete Emergency Container");
$d->move_and_click('//*[@id="emergency_containers_table"]/tbody/tr/td[4]/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="emergency_containers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Emergency Container has been deleted");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), 'Emergency mapping container successfully deleted',  'Correct Alert was shown');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Emergency Container has been deleted');
$d->find_element('//*[@id="content"]//div//a[contains(text(), "Back")]')->click();

$c->delete_domain($domainstring);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_emergency.png");
    }
    $d->quit();
    done_testing;
}