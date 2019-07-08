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

my $groupname = ("group" . int(rand(100000)) . "test");
my $servername = ("peering" . int(rand(100000)) . "server");
my $run_ok = 0;

$c->login_ok();

diag("Go to Peerings page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Peerings", 'link_text')->click();

diag("Create a empty Peering Group");
$d->find_element('//*[@id="masthead"]//h2[contains(text(),"SIP Peering Groups")]');
my $peerings_uri = $d->get_current_url();
$d->find_element('Create Peering Group', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Contract field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));

diag("Create a new Contract");
$d->find_element('//input[@type="button" and @value="Create Contract"]')->click();
$d->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#contactidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'default-system@default.invalid');
ok($d->wait_for_text('//*[@id="contactidtable"]/tbody/tr[1]/td[4]', 'default-system@default.invalid'), "Default Contact was found");
$d->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->scroll_to_element($d->find_element('//table[@id="billing_profileidtable"]'));
$d->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->find_element('//*[@id="status"]/option[@value="active"]')->click();
$d->find_element('//*[@id="save"]')->click();
ok($d->find_text('Create Peering Group'), 'Succesfully went back to previous form'); # Should go back to prev form

diag("Continue creating a Peering Group");
$d->fill_element('#name', 'css', $groupname);
$d->fill_element('#description', 'css', 'A group created for testing purposes');
$d->find_element('//*[@id="priority"]/option[@value="3"]')->click();
$d->select_if_unselected('//table[@id="contractidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->find_element('#save', 'css')->click();

diag("Search for the newly created Peering Group");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering group successfully created",  "Correct Alert was shown");
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);

diag("Check Peering Group Details");
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[2]', 'default-system@default.invalid'), 'Contact is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Name is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[4]', '3'), 'Priority is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[5]', 'A group created for testing purposes'), 'Description is correct');

diag("Edit Peering Group");
$groupname = ("group" . int(rand(100000)) . "test");
$d->move_and_click('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Edit")]', 'xpath');
$d->fill_element('#name', 'css', $groupname);
$d->fill_element('#description', 'css', 'A group created for very testing purposes');
$d->find_element('//*[@id="priority"]/option[@value="1"]')->click();
$d->find_element('#save', 'css')->click();

diag("Search for the newly created Peering Group");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering group successfully updated",  "Correct Alert was shown");
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);

diag("Check Peering Group Details");
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[2]', 'default-system@default.invalid'), 'Contact is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Name is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[4]', '1'), 'Priority is correct');
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[5]', 'A group created for very testing purposes'), 'Description is correct');

diag("Go to Details of the Peering Group");
$d->move_and_click('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Details")]', 'xpath');

diag("Create empty Outbound Peering Rule");
$d->find_element('//a[contains(text(),"Create Outbound Peering Rule")]')->click();
$d->find_element('#save', 'css')->click();

diag("Check if it was created");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering rule successfully created",  "Correct Alert was shown");

diag("Delete empty Outbound Peering Rule");
ok($d->move_and_click('//*[@id="PeeringRules_table"]//tr[1]//td//a[contains(text(), "Delete")]', 'xpath', '//*[@id="PeeringRules_table_filter"]//input'));
$d->find_element('#dataConfirmOK', 'css')->click();
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering rule successfully deleted",  "Correct Alert was shown");

diag("Create Outbound Peering Rule");
$d->find_element('//a[contains(text(),"Create Outbound Peering Rule")]')->click();
$d->fill_element('#callee_prefix', 'css', '43');
$d->fill_element('#callee_pattern', 'css', '^sip');
$d->fill_element('#caller_pattern', 'css', '999');
$d->fill_element('#description', 'css', 'for testing purposes');
$d->find_element('#save', 'css')->click();

diag("Check Outbound Peering Rule Details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering rule successfully created",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "43")]'), "Prefix is correct");
ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "^sip")]'), "Callee Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "999")]'), "Caller Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "for testing purposes")]'), "Description is correct");

diag("Edit Outbound Peering Rule Details");
$d->move_and_click('//*[@id="PeeringRules_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="PeeringRules_table_filter"]//input');
$d->fill_element('#callee_prefix', 'css', '49');
$d->fill_element('#callee_pattern', 'css', '^sup');
$d->fill_element('#caller_pattern', 'css', '888');
$d->fill_element('#description', 'css', 'for very testing purposes');
$d->find_element('#save', 'css')->click();

diag("Check Outbound Peering Rule Details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering rule successfully changed",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "49")]'), "Prefix is correct");
ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "^sup")]'), "Callee Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "888")]'), "Caller Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "for very testing purposes")]'), "Description is correct");

diag("Create empty Inbound Peering Rule");
$d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]')->click();
$d->find_element('#save', 'css')->click();

diag("Check if creation failed");
ok($d->find_element_by_xpath('//*[@id="content"]//div[contains(text(), "Failed to create inbound peering rule")]'), "Correct Alert was shown");

diag("Create Inbound Peering Rule");
$d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]')->click();
$d->fill_element('//*[@id="pattern"]', 'xpath', '^sip');
$d->fill_element('//*[@id="reject_code"]', 'xpath', '403');
$d->fill_element('//*[@id="reject_reason"]', 'xpath', 'forbidden');
$d->find_element('#save', 'css')->click();

diag("Check Inbound Peering Rule Details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Inbound peering rule successfully created",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "^sip")]'), "Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "403")]'), "Reject Code is correct");
ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "forbidden")]'), "Reject Reason is correct");

diag("Edit Inbound Peering Rule Details");
$d->scroll_to_element($d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]'));
$d->move_and_click('//*[@id="InboundPeeringRules_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="InboundPeeringRules_table_filter"]//input');
$d->fill_element('//*[@id="pattern"]', 'xpath', '^sup');
$d->fill_element('//*[@id="reject_code"]', 'xpath', '404');
$d->fill_element('//*[@id="reject_reason"]', 'xpath', 'not found');
$d->find_element('#save', 'css')->click();

diag("Check Inbound Peering Rule Details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Inbound peering rule successfully changed",  "Correct Alert was shown");
ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "^sup")]'), "Pattern is correct");
ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "404")]'), "Reject Code is correct");
ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "not found")]'), "Reject Reason is correct");

diag("Create a empty Peering Server");
$d->find_element('//a[contains(text(),"Create Peering Server")]')->click();
$d->find_element('#save', 'css')->click();

diag("Check Error Messages");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Name field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "IP Address field is required")]'));

diag("Fill in values");
$d->fill_element('#name', 'css', $servername);
$d->fill_element('#ip', 'css', '10.0.0.100');
$d->fill_element('#host', 'css', 'sipwise.com');
$d->find_element('#save', 'css')->click();
ok($d->find_text('Peering server successfully created'), 'Text "Peering server successfully created" appears');
my $server_rules_uri = $d->get_current_url();

diag("Check Peering Server Details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering server successfully created",  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr/td[2]', $servername), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="peering_servers_table"]/tbody/tr/td[contains(text(), "10.0.0.100")]'), "IP is correct");
ok($d->find_element_by_xpath('//*[@id="peering_servers_table"]/tbody/tr/td[contains(text(), "sipwise.com")]'), "Host is correct");

diag("Edit Peering Server Details");
$servername = ("peering" . int(rand(100000)) . "server");
$d->move_and_click('//*[@id="peering_servers_table"]//tr[1]//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="peering_servers_table_filter"]//input');
$d->fill_element('#name', 'css', $servername);
$d->fill_element('#ip', 'css', '10.0.1.101');
$d->fill_element('#host', 'css', 'google.at');
$d->find_element('#save', 'css')->click();

diag("Check Peering Server Details");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering server successfully updated",  "Correct Alert was shown");
ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr/td[2]', $servername), "Name is correct");
ok($d->find_element_by_xpath('//*[@id="peering_servers_table"]/tbody/tr/td[contains(text(), "10.0.1.101")]'), "IP is correct");
ok($d->find_element_by_xpath('//*[@id="peering_servers_table"]/tbody/tr/td[contains(text(), "google.at")]'), "Host is correct");

diag('Go into Peering Server Preferences');
$d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#peering_servers_table tr > td.dataTables_empty', 'css');
$d->fill_element('#peering_servers_table_filter input', 'css', $servername);
ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr[1]/td[2]', $servername), 'Peering Server has been found');
$d->move_and_click('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Preferences")]', 'xpath', '//*[@id="peering_servers_table_filter"]//input');

diag('Open the tab "Number Manipulations"');
$d->find_element("Number Manipulations", 'link_text')->click();

diag("Click edit for the preference inbound_upn");
$d->move_and_click('//table//td[contains(text(), "inbound_upn")]/..//td//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Number Manipulation")]');

diag('Change to "P-Asserted-Identity');
$d->find_element('//*[@id="inbound_upn"]/option[@value="pai_user"]')->click();
$d->find_element('#save', 'css')->click();

diag('Check if value has been applied');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference inbound_upn successfully updated",  "Correct Alert was shown");
ok($d->wait_for_text('//table//td[contains(text(), "inbound_upn")]/../td/select/option[@selected="selected"]', "P-Asserted-Identity"), "Value has been applied");

diag('Open the tab "Remote Authentication"');
$d->scroll_to_element($d->find_element("Remote Authentication", 'link_text'));
$d->find_element("Remote Authentication", 'link_text')->click();

diag('Edit peer_auth_user');
$d->move_and_click('//table/tbody/tr/td[contains(text(), "peer_auth_user")]/../td/div//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Remote Authentication")]');
$d->fill_element('//*[@id="peer_auth_user"]', 'xpath', 'peeruser1');
$d->find_element('#save', 'css')->click();

diag('Check if peer_auth_user value has been set');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference peer_auth_user successfully updated",  "Correct Alert was shown");
$d->find_element("Remote Authentication", 'link_text')->click();
ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_user")]/../td[4]', 'peeruser1'), 'peer_auth_user value has been set');

diag('Edit peer_auth_pass');
$d->move_and_click('//table/tbody/tr/td[contains(text(), "peer_auth_pass")]/../td/div//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Remote Authentication")]');
$d->fill_element('//*[@id="peer_auth_pass"]', 'xpath', 'peerpass1');
$d->find_element('#save', 'css')->click();

diag('Check if peer_auth_pass value has been set');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference peer_auth_pass successfully updated",  "Correct Alert was shown");
$d->find_element("Remote Authentication", 'link_text')->click();
ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_pass")]/../td[4]', 'peerpass1'), 'peer_auth_pass value has been set');

diag('Edit peer_auth_realm');
$d->move_and_click('//table/tbody/tr/td[contains(text(), "peer_auth_realm")]/../td/div//a[contains(text(), "Edit")]', 'xpath', '//*[@id="preference_groups"]//div//a[contains(text(), "Remote Authentication")]');
$d->fill_element('//*[@id="peer_auth_realm"]', 'xpath', 'testpeering.com');
$d->find_element('#save', 'css')->click();

diag('Check if peer_auth_realm value has been set');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference peer_auth_realm successfully updated",  "Correct Alert was shown");
$d->find_element("Remote Authentication", 'link_text')->click();
ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_realm")]/../td[4]', 'testpeering.com'), 'peer_auth_realm value has been set');

diag("Go back to Servers/Rules");
$d->get($server_rules_uri);

diag("Delete mytestserver");
$d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#peering_servers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#peering_servers_table_filter input', 'css', $servername);
ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr/td[2]', $servername), "mytestserver was found");
$d->move_and_click('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]', 'xpath', '//*[@id="peering_servers_table_filter"]//input');
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag("Check if Peering server was deleted");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering server successfully deleted",  "Correct Alert was shown");
ok($d->find_element_by_css('#peering_servers_table tr > td.dataTables_empty', 'css'), 'Peering Server was deleted');

diag("Delete the Outbound Peering Rule");
$d->fill_element('#PeeringRules_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#PeeringRules_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#PeeringRules_table_filter input', 'css', 'for very testing purposes');
ok($d->wait_for_text('//*[@id="PeeringRules_table"]/tbody/tr/td[5]', 'for very testing purposes'), "Outbound Peering Rule was found");
$d->move_and_click('//*[@id="PeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]', 'xpath', '//*[@id="PeeringRules_table_filter"]//input');
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag("Check if Outbound peering rule was deleted");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering rule successfully deleted",  "Correct Alert was shown");
ok($d->find_element_by_css('#PeeringRules_table tr > td.dataTables_empty', 'css'), 'Outbound peering rule was deleted');

diag("Delete the Inbound Peering Rule");
$d->scroll_to_element($d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]'));
$d->fill_element('#InboundPeeringRules_table_filter input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#InboundPeeringRules_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#InboundPeeringRules_table_filter input', 'css', 'not found');
ok($d->wait_for_text('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[6]', 'not found'), "Inbound Peering Rule was found");
$d->move_and_click('//*[@id="InboundPeeringRules_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]', 'xpath', '//*[@id="InboundPeeringRules_table_filter"]//input');
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag("Check if Inbound peering rule was delted");
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Inbound peering rule successfully deleted",  "Correct Alert was shown");
ok($d->find_element_by_css('#InboundPeeringRules_table tr > td.dataTables_empty', 'css'), 'Inbound peering rule was deleted');

diag('Go back to "SIP Peering Groups".');
$d->get($peerings_uri);

diag('Trying to NOT delete Testinggroup');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Testing Group was found');
$d->move_and_click('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]', 'xpath', '//*[@id="sip_peering_group_table_filter"]//input');
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmCancel', 'css')->click();

diag('Checking if Testing Group has been deleted');
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Testinggroup is still here');

diag('Trying to delete Testinggroup');
$d->move_and_click('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Delete")]', 'xpath', '//*[@id="sip_peering_group_table_filter"]//input');
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag('Checking if Testing Group has been deleted');
is($d->get_text('//*[@id="content"]//div[contains(@class, "alert")]'), "Peering Group successfully deleted",  "Correct Alert was shown");
$d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Testing Group was deleted');

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_peering.png");
    }
    done_testing;
}