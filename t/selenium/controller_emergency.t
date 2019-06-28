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

diag("Go to Emergency Mappings page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Emergency Mappings", 'link_text')->click();

diag("Trying to create a empty emergency container");
$d->find_element("Create Emergency Container", 'link_text')->click();
$d->unselect_if_selected('//*[@id="reselleridtable"]//tr[1]//td//input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Fill in values");
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#reselleridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="reselleridtable_filter"]/label/input', 'xpath', $resellername);
ok($d->wait_for_text('//*[@id="reselleridtable"]/tbody/tr[1]/td[2]', $resellername), "Reseller found");
$d->select_if_unselected('//*[@id="reselleridtable"]/tbody/tr[1]/td[5]/input', 'xpath');
$d->fill_element('//*[@id="name"]', 'xpath', $containername);
$d->find_element('//*[@id="save"]')->click();

diag("Search for our new Emergency Container");
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);

diag("Check Emergency Container details");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Emergency mapping container successfully created")]'), "Label 'Emergency mapping container successfully created' was shown");
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]/tbody/tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]/tbody/tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container name is correct');

diag("Edit Container name");
$containername = ("emergency" . int(rand(100000)) . "container");
$d->move_and_click('//*[@id="emergency_containers_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="emergency_containers_table_filter"]//input');
$d->fill_element('//*[@id="name"]', 'xpath', $containername);
$d->find_element('//*[@id="save"]')->click();

diag("Search for our new Emergency Container");
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);

diag("Check Emergency Container details");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Emergency mapping container successfully updated")]'), "Label 'Emergency mapping container successfully updated' was shown");
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]/tbody/tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]/tbody/tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container name is correct');

diag("Trying to create a empty Emergency Mapping");
$d->find_element("Create Emergency Mapping", 'link_text')->click();
$d->unselect_if_selected('//*[@id="emergency_containeridtable"]//tr[1]//td//input');
$d->find_element('//*[@id="save"]')->click();

diag("Check error messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Emergency Mapping Container field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Code field is required")]'));

diag("Fill in Values");
$d->fill_element('//*[@id="emergency_containeridtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containeridtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containeridtable_filter"]/label/input', 'xpath', $containername);
ok($d->wait_for_text('//*[@id="emergency_containeridtable"]/tbody/tr[1]/td[3]', $containername), "Emergency Container found");
$d->select_if_unselected('//*[@id="emergency_containeridtable"]/tbody/tr[1]/td[4]/input', 'xpath');
$d->fill_element('//*[@id="code"]', 'xpath', "133");
$d->fill_element('//*[@id="prefix"]', 'xpath', "E1_133_");
$d->find_element('//*[@id="save"]')->click();

diag("Search for our new Emergency Mapping");
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);

diag("Check Emergency Mapping details");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Emergency mapping successfully created")]'), "Label 'Emergency mapping successfully created' was shown");
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container name is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), "133")]'), 'Emergency Number is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), "E1_133_")]'), 'Emergency Prefix is correct');

diag("Edit Emergency Mapping Details");
$d->move_and_click('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[6]/div/a[2]', 'xpath', '//*[@id="emergency_mappings_table_filter"]//input');
$d->fill_element('//*[@id="code"]', 'xpath', "144");
$d->fill_element('//*[@id="prefix"]', 'xpath', "E2_144_");
$d->find_element('//*[@id="save"]')->click();

diag("Search for our new Emergency Mapping");
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);

diag("Check Emergency Mapping details");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Emergency mapping successfully updated")]'), "Label 'Emergency mapping successfully updated' was shown");
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container name is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), ' . $resellername . ')]'), 'Reseller is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), "144")]'), 'Emergency Number is correct');
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), "E2_144_")]'), 'Emergency Prefix is correct');

diag("Creating Domain to add Emergency Container");
$c->create_domain($domainstring, $resellername);

diag("Searching Domain");
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[contains(text(), "domain")]', $domainstring), "Domain was found");
$d->move_and_click('//*[@id="Domain_table"]//tr[1]//td//a[contains(text(), "Preferences")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');

diag("Open 'Number Manipulations'");
$d->find_element("Number Manipulations", 'link_text')->click();
$d->scroll_to_element($d->find_element('//*[@id="preference_groups"]//div//a[contains(text(),"Number Manipulations")]'));

diag("Edit setting 'emergency_mapping_container'");
$d->scroll_to_element($d->find_element('//table//tr//td[contains(text(), "emergency_mapping_container")]'));
$d->move_and_click('//table//tr//td[contains(text(), "emergency_mapping_container")]/../td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "NAT and Media Flow Control")]');
$d->find_element('//*[@id="emergency_mapping_container"]/option[contains(text(), "' . $containername . '")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if 'emergency_mapping_container' was applied");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Preference emergency_mapping_container successfully updated")]'), "Label 'Preference emergency_mapping_container successfully updated' was shown");
ok($d->find_element_by_xpath('//table//tr//td[contains(text(), "emergency_mapping_container")]/../td/select/option[contains(text(), "' . $containername . '")][@selected="selected"]'), 'NCOS Level was applied');

diag("Open 'Internals'");
$d->find_element("Internals", 'link_text')->click();
$d->scroll_to_element($d->find_element('//*[@id="preference_groups"]//div//a[contains(text(),"Internals")]'));

diag("Edit setting 'emergency_mode_enabled'");
$d->scroll_to_element($d->find_element('//table//tr//td[contains(text(), "emergency_mode_enabled")]'));
$d->move_and_click('//table//tr//td[contains(text(), "emergency_mode_enabled")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr//td[contains(text(), "call_deflection")]');
$d->select_if_unselected('//*[@id="emergency_mode_enabled"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check if Setting was enabled");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Preference emergency_mode_enabled successfully updated")]'), "Label 'Preference emergency_mode_enabled successfully updated' was shown");
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "emergency_mode_enabled")]/../td//input[@checked="checked"]'), "Setting was enabled");

diag("Go to Emergency Mappings page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Emergency Mappings", 'link_text')->click();

diag("Trying to NOT delete Emergency Mapping");
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);
ok($d->wait_for_text('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[2]', $containername), 'Emergency mapping was found');
$d->move_and_click('//*[@id="emergency_mappings_table"]/tbody/tr/td[6]/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="emergency_mappings_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Emergency Mapping is still here");
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_xpath('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[contains(text(), ' . $containername . ')]'), 'Mapping is still here');

diag("Trying to delete Emergency Mapping");
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);
ok($d->wait_for_text('//*[@id="emergency_mappings_table"]/tbody/tr[1]/td[2]', $containername), 'Emergency mapping was found');
$d->move_and_click('//*[@id="emergency_mappings_table"]/tbody/tr/td[6]/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="emergency_mappings_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Emergency Mapping was deleted");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Emergency mapping successfully deleted")]'), "Label 'Emergency mapping successfully deleted' was shown");
$d->fill_element('//*[@id="emergency_mappings_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_css('#emergency_mappings_table tr > td.dataTables_empty', 'css'), 'Emergency Mapping was deleted');

diag("Trying to NOT delete Emergency Container");
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);
ok($d->wait_for_text('//*[@id="emergency_containers_table"]/tbody/tr[1]/td[3]', $containername), 'Emergency mapping was found');
$d->move_and_click('//*[@id="emergency_containers_table"]/tbody/tr/td[4]/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="emergency_containers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmCancel"]')->click();

diag("Check if Emergency Container is still here");
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_xpath('//*[@id="emergency_containers_table"]/tbody/tr[1]/td[contains(text(), ' . $containername . ')]'), 'Container is still here');

diag("Trying to delete Emergency Container");
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);
ok($d->wait_for_text('//*[@id="emergency_containers_table"]/tbody/tr[1]/td[3]', $containername), 'Emergency mapping was found');
$d->move_and_click('//*[@id="emergency_containers_table"]/tbody/tr/td[4]/div/a[contains(text(), "Delete")]', 'xpath', '//*[@id="emergency_containers_table_filter"]/label/input');
$d->find_element('//*[@id="dataConfirmOK"]')->click();

diag("Check if Emergency Container was deleted");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Emergency mapping container successfully deleted")]'), "Label 'Emergency mapping container successfully deleted' was shown");
$d->fill_element('//*[@id="emergency_containers_table_filter"]/label/input', 'xpath', $containername);
ok($d->find_element_by_css('#emergency_containers_table tr > td.dataTables_empty', 'css'), 'Emergency Mapping was deleted');

$c->delete_domain($domainstring);
$c->delete_reseller_contract($contractid);
$c->delete_reseller($resellername);

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        is("tests", "failed", "This test wasnt successful, check complete test logs for more info");
        diag("-----------------------SCRIPT HAS CRASHED-----------------------");
        my $url = $d->get_current_url();
        my $title = $d->get_title();
        my $realtime = localtime();
        if($d->find_text("Sorry!") || $d->find_text("Oops!")) {
            my $crashvar = $d->find_element_by_css('.error-container > h2:nth-child(2)')->get_text();
            my $incident = "incident number: not avalible";
            my $time = "time of incident: not avalible";
            eval {
                $incident = $d->find_element('.error-details > div:nth-child(2)', 'css')->get_text();
                $time = $d->find_element('.error-details > div:nth-child(3)', 'css')->get_text();
            };
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Url: $url");
            diag("Tab Title: $title");
            diag("Server error: $crashvar");
            diag($incident);
            diag($time);
            diag("Perl localtime(): $realtime");
        } elsif($d->find_text("nginx")) {
            my $crashvar = $d->find_element_by_css('body > center:nth-child(1) > h1:nth-child(1)')->get_text();
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Url: $url");
            diag("Tab Title: $title");
            diag("nginx error: $crashvar");
            diag("Perl localtime(): $realtime");
        } elsif($d->find_element('//*[@id="content"]//div[@class="alert alert-error"]')) {
            my $label = "Label: could not get text";
            eval {
                $label = $d->find_element('//*[@id="content"]//div[@class="alert alert-error"]')->get_text();
            };
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Url: $url");
            diag("Tab Title: $title");
            diag("Error Label: $label");
            diag("Perl localtime(): $realtime");
        } else {
            diag("Could not detect Server issues. Maybe script problems?");
            diag("If you still want to check server logs, here's some info");
            diag("Server: $ENV{CATALYST_SERVER}");
            diag("Url: $url");
            diag("Tab Title: $title");
            diag("Perl localtime(): $realtime");
        }
        diag("----------------------------------------------------------------");
    };
    done_testing;
}