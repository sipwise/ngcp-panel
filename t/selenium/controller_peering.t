use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
);

$d->login_ok();

my $groupname = ("testinggroup" . int(rand(10000))); #create string for checking later

diag("Go to Peerings page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Peerings", 'link_text')->click();

diag("Create a Peering Group");
$d->find_element('//*[@id="masthead"]//h2[contains(text(),"SIP Peering Groups")]');
my $peerings_uri = $d->get_current_url();
$d->find_element('Create Peering Group', 'link_text')->click();

diag("Create a Peering Contract");
$d->find_element('//input[@type="button" and @value="Create Contract"]')->click();
$d->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]//input[@type="checkbox"]');
my $elem = $d->find_element('//table[@id="billing_profileidtable"]');
$d->scroll_to_element($elem);
$d->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->find_element('//div[contains(@class,"modal-body")]//div//select[@id="status"]/option[@value="active"]')->click();
$d->find_element('//div[contains(@class,"modal")]//input[@type="submit"]')->click();
ok($d->find_text('Create Peering Group'), 'Succesfully went back to previous form'); # Should go back to prev form

$d->fill_element('#name', 'css', $groupname);
$d->fill_element('#description', 'css', 'A group created for testing purposes');
$d->select_if_unselected('//table[@id="contractidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->find_element('#save', 'css')->click();
sleep 1;

diag("Edit Servers/Rules of testinggroup");
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Testing Group was found');
$d->move_action(element=> $d->find_element('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Details")]'));
$d->find_element('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Details")]')->click();

diag("Create Outbound Peering Rule");
$d->find_element('//a[contains(text(),"Create Outbound Peering Rule")]')->click();
$d->fill_element('#callee_prefix', 'css', '43');
$d->fill_element('#callee_pattern', 'css', '^sip');
$d->fill_element('#caller_pattern', 'css', '999');
$d->fill_element('#description', 'css', 'for testing purposes');
$d->find_element('#save', 'css')->click();

diag("Create Inbound Peering Rule");
$d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]')->click();
$d->fill_element('//*[@id="pattern"]', 'xpath', '^sip');
$d->fill_element('//*[@id="reject_code"]', 'xpath', '403');
$d->fill_element('//*[@id="reject_reason"]', 'xpath', 'forbidden');
$d->find_element('#save', 'css')->click();

diag("Create a Peering Server");
$d->find_element('//a[contains(text(),"Create Peering Server")]')->click();
$d->fill_element('#name', 'css', 'mytestserver');
$d->fill_element('#ip', 'css', '10.0.0.100');
$d->fill_element('#host', 'css', 'sipwise.com');
$d->find_element('#save', 'css')->click();
ok($d->find_text('Peering server successfully created'), 'Text "Peering server successfully created" appears');
my $server_rules_uri = $d->get_current_url();

diag('Edit Preferences for "mytestserver".');
sleep 1; #make sure, we are on the right page
$d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#peering_servers_table tr > td.dataTables_empty', 'css');
$d->fill_element('#peering_servers_table_filter input', 'css', 'mytestserver');
my $edit_link = $d->find_element('//table/tbody/tr/td[contains(text(), "mytestserver")]/../td//a[contains(text(),"Preferences")]');
my $row = $d->find_element('//table/tbody/tr/td[contains(text(), "mytestserver")]/..');
ok($row);
ok($edit_link);
$d->move_action(element => $row);
$edit_link->click();

diag('Open the tab "Number Manipulations"');
$d->find_element("Number Manipulations", 'link_text')->click();

diag("Click edit for the preference inbound_upn");
$row = $d->find_element('//table/tbody/tr/td[normalize-space(text()) = "inbound_upn"]');
ok($row);
$edit_link = $d->find_child_element($row, '(./../td//a)[2]');
ok($edit_link);
$d->move_action(element => $row);
$edit_link->click();

diag('Change to "P-Asserted-Identity');
$d->find_element('//div[contains(@class,"modal-body")]//select[@id="inbound_upn"]/option[@value="pai_user"]')->click();
$d->find_element('#save', 'css')->click();
ok($d->find_text('Preference inbound_upn successfully updated'), 'Text "Preference inbound_upn successfully updated" appears');

diag('Open the tab "Remote Authentication"');
$d->scroll_to_element($d->find_element("Remote Authentication", 'link_text'));
$d->find_element("Remote Authentication", 'link_text')->click();

diag('Edit peer_auth_user');
$d->move_action(element => $d->find_element('//*[@id="preferences_table6"]/tbody/tr[1]/td//div//a[contains(text(), "Edit")]'));
$d->find_element('//*[@id="preferences_table6"]/tbody/tr[1]/td//div//a[contains(text(), "Edit")]')->click();
$d->fill_element('//*[@id="peer_auth_user"]', 'xpath', 'peeruser1');
$d->find_element('#save', 'css')->click();

diag('Edit peer_auth_pass');
$d->find_element("Remote Authentication", 'link_text')->click();
$d->move_action(element => $d->find_element('//*[@id="preferences_table6"]/tbody/tr[2]/td//div//a[contains(text(), "Edit")]'));
$d->find_element('//*[@id="preferences_table6"]/tbody/tr[2]/td//div//a[contains(text(), "Edit")]')->click();
$d->fill_element('//*[@id="peer_auth_pass"]', 'xpath', 'peerpass1');
$d->find_element('#save', 'css')->click();

diag('Edit peer_auth_realm');
$d->find_element("Remote Authentication", 'link_text')->click();
$d->move_action(element => $d->find_element('//*[@id="preferences_table6"]/tbody/tr[3]/td//div//a[contains(text(), "Edit")]'));
$d->find_element('//*[@id="preferences_table6"]/tbody/tr[3]/td//div//a[contains(text(), "Edit")]')->click();
$d->fill_element('//*[@id="peer_auth_realm"]', 'xpath', 'testpeering.com');
$d->find_element('#save', 'css')->click();

diag("Go back to Servers/Rules");
$d->get($server_rules_uri);

diag('skip was here');
diag("Delete mytestserver");
$d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#peering_servers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#peering_servers_table_filter input', 'css', 'mytestserver');
ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr/td[2]', 'mytestserver'), "mytestserver was found");
$d->move_action(element => $d->find_element('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
$d->find_element('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();
ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

diag("Delete the Outbound Peering Rule");
$d->fill_element('#PeeringRules_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#PeeringRules_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#PeeringRules_table_filter input', 'css', 'for testing purposes');
ok($d->wait_for_text('//*[@id="PeeringRules_table"]/tbody/tr/td[5]', 'for testing purposes'), "Outbound Peering Rule was found");
$d->move_action(element => $d->find_element('//*[@id="PeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
$d->find_element('//*[@id="PeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();
ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

diag("Delete the Inbound Peering Rule");
$d->scroll_to_element($d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]'));
$d->fill_element('#InboundPeeringRules_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#InboundPeeringRules_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#InboundPeeringRules_table_filter input', 'css', 'forbidden');
ok($d->wait_for_text('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[6]', 'forbidden'), "Inbound Peering Rule was found");
$d->move_action(element => $d->find_element('//*[@id="InboundPeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
$d->find_element('//*[@id="InboundPeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();
ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

diag('Go back to "SIP Peering Groups".');
$d->get($peerings_uri);

diag('Delete Testing Group');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Testing Group was found');
$d->move_action(element=> $d->find_element('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]'));
$d->find_element('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag('Checking if Testing Group has been deleted');
ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Testing Group was deleted');

done_testing;
# vim: filetype=perl
