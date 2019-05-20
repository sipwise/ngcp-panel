use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;

sub ctr_peering {
    my ($port) = @_;
    return unless $port;

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

    my $groupname = ("group" . int(rand(100000)) . "test");
    my $servername = ("peering" . int(rand(100000)) . "server");

    $c->login_ok();

    diag("Go to Peerings page");
    $d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
    $d->find_element("Peerings", 'link_text')->click();

    diag("Create a Peering Group");
    $d->find_element('//*[@id="masthead"]//h2[contains(text(),"SIP Peering Groups")]');
    my $peerings_uri = $d->get_current_url();
    $d->find_element('Create Peering Group', 'link_text')->click();

    diag("Create a Peering Contract");
    $d->find_element('//input[@type="button" and @value="Create Contract"]')->click();
    $d->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#contactidtable tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="contactidtable_filter"]/label/input', 'xpath', 'default-system@default.invalid');
    ok($d->wait_for_text('//*[@id="contactidtable"]/tbody/tr[1]/td[4]', 'default-system@default.invalid'), "Default Contact was found");
    $d->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]//input[@type="checkbox"]');
    $d->scroll_to_element($d->find_element('//table[@id="billing_profileidtable"]'));
    $d->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]//input[@type="checkbox"]');
    $d->find_element('//div[contains(@class,"modal-body")]//div//select[@id="status"]/option[@value="active"]')->click();
    $d->find_element('//div[contains(@class,"modal")]//input[@type="submit"]')->click();
    ok($d->find_text('Create Peering Group'), 'Succesfully went back to previous form'); # Should go back to prev form

    diag("Continue creating a Peering Group");
    $d->fill_element('#name', 'css', $groupname);
    $d->fill_element('#description', 'css', 'A group created for testing purposes');
    $d->select_if_unselected('//table[@id="contractidtable"]/tbody/tr[1]//input[@type="checkbox"]');
    $d->find_element('#save', 'css')->click();

    diag("Search for the newly created Peering Group");
    $d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
    ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);

    diag("Check Peering Group Details");
    ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[2]', 'default-system@default.invalid'), 'Contact is correct');
    ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[3]', $groupname), 'Name is correct');
    ok($d->wait_for_text('//*[@id="sip_peering_group_table"]/tbody/tr/td[5]', 'A group created for testing purposes'), 'Description is correct');

    diag("Edit Peering Group");
    $d->move_and_click('//*[@id="sip_peering_group_table"]/tbody/tr[1]//td//div//a[contains(text(), "Details")]', 'xpath');

    diag("Create Outbound Peering Rule");
    $d->find_element('//a[contains(text(),"Create Outbound Peering Rule")]')->click();
    $d->fill_element('#callee_prefix', 'css', '43');
    $d->fill_element('#callee_pattern', 'css', '^sip');
    $d->fill_element('#caller_pattern', 'css', '999');
    $d->fill_element('#description', 'css', 'for testing purposes');
    $d->find_element('#save', 'css')->click();

    diag("Check Outbound Peering Rule Details");
    ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "43")]'), "Prefix is correct");
    ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "^sip")]'), "Callee Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "999")]'), "Caller Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="PeeringRules_table"]/tbody/tr/td[contains(text(), "for testing purposes")]'), "Description is correct");

    diag("Create Inbound Peering Rule");
    $d->find_element('//a[contains(text(),"Create Inbound Peering Rule")]')->click();
    $d->fill_element('//*[@id="pattern"]', 'xpath', '^sip');
    $d->fill_element('//*[@id="reject_code"]', 'xpath', '403');
    $d->fill_element('//*[@id="reject_reason"]', 'xpath', 'forbidden');
    $d->find_element('#save', 'css')->click();

    diag("Check Inbound Peering Rule Details");
    ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "^sip")]'), "Pattern is correct");
    ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "403")]'), "Reject Code is correct");
    ok($d->find_element_by_xpath('//*[@id="InboundPeeringRules_table"]/tbody/tr/td[contains(text(), "forbidden")]'), "Reject Reason is correct");

    diag("Create a Peering Server");
    $d->find_element('//a[contains(text(),"Create Peering Server")]')->click();
    $d->fill_element('#name', 'css', $servername);
    $d->fill_element('#ip', 'css', '10.0.0.100');
    $d->fill_element('#host', 'css', 'sipwise.com');
    $d->find_element('#save', 'css')->click();
    ok($d->find_text('Peering server successfully created'), 'Text "Peering server successfully created" appears');
    my $server_rules_uri = $d->get_current_url();

    diag("Check Peering Server Details");
    ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr/td[2]', $servername), "Name is correct");
    ok($d->find_element_by_xpath('//*[@id="peering_servers_table"]/tbody/tr/td[contains(text(), "10.0.0.100")]'), "IP is correct");
    ok($d->find_element_by_xpath('//*[@id="peering_servers_table"]/tbody/tr/td[contains(text(), "sipwise.com")]'), "Host is correct");

    diag('Go into Peering Server Preferences');
    $d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
    $d->find_element('#peering_servers_table tr > td.dataTables_empty', 'css');
    $d->fill_element('#peering_servers_table_filter input', 'css', $servername);
    ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr[1]/td[2]', $servername), 'Peering Server has been found');
    $d->move_action(element => $d->find_element('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Preferences")]'));
    $d->find_element('//*[@id="peering_servers_table"]/tbody/tr[1]//td//div//a[contains(text(), "Preferences")]')->click();

    diag('Open the tab "Number Manipulations"');
    $d->find_element("Number Manipulations", 'link_text')->click();

    diag("Click edit for the preference inbound_upn");
    $d->move_action(element => $d->find_element('//table//td[contains(text(), "inbound_upn")]/..//td//a[contains(text(), "Edit")]'));
    $d->find_element('//table//td[contains(text(), "inbound_upn")]/..//td//a[contains(text(), "Edit")]')->click();

    diag('Change to "P-Asserted-Identity');
    $d->find_element('//*[@id="inbound_upn"]/option[@value="pai_user"]')->click();
    $d->find_element('#save', 'css')->click();

    diag('Check if value has been applied');
    ok($d->find_text('Preference inbound_upn successfully updated'), 'Text "Preference inbound_upn successfully updated" appears');
    ok($d->wait_for_text('//table//td[contains(text(), "inbound_upn")]/../td/select/option[@selected="selected"]', "P-Asserted-Identity"), "Value has been applied");

    diag('Open the tab "Remote Authentication"');
    $d->scroll_to_element($d->find_element("Remote Authentication", 'link_text'));
    $d->find_element("Remote Authentication", 'link_text')->click();

    diag('Edit peer_auth_user');
    $d->move_action(element => $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_user")]/../td/div//a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_user")]/../td/div//a[contains(text(), "Edit")]')->click();
    $d->fill_element('//*[@id="peer_auth_user"]', 'xpath', 'peeruser1');
    $d->find_element('#save', 'css')->click();

    diag('Check if peer_auth_user value has been set');
    ok($d->find_text('Preference peer_auth_user successfully updated'), 'Text "Preference peer_auth_user successfully updated" appears');
    $d->find_element("Remote Authentication", 'link_text')->click();
    ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_user")]/../td[4]', 'peeruser1'), 'peer_auth_user value has been set');

    diag('Edit peer_auth_pass');
    $d->move_action(element => $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_pass")]/../td/div//a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_pass")]/../td/div//a[contains(text(), "Edit")]')->click();
    $d->fill_element('//*[@id="peer_auth_pass"]', 'xpath', 'peerpass1');
    $d->find_element('#save', 'css')->click();

    diag('Check if peer_auth_pass value has been set');
    ok($d->find_text('Preference peer_auth_pass successfully updated'), 'Text "Preference peer_auth_pass successfully updated" appears');
    $d->find_element("Remote Authentication", 'link_text')->click();
    ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_pass")]/../td[4]', 'peerpass1'), 'peer_auth_pass value has been set');

    diag('Edit peer_auth_realm');
    $d->move_action(element => $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_realm")]/../td/div//a[contains(text(), "Edit")]'));
    $d->find_element('//table/tbody/tr/td[contains(text(), "peer_auth_realm")]/../td/div//a[contains(text(), "Edit")]')->click();
    $d->fill_element('//*[@id="peer_auth_realm"]', 'xpath', 'testpeering.com');
    $d->find_element('#save', 'css')->click();

    diag('Check if peer_auth_realm value has been set');
    ok($d->find_text('Preference peer_auth_realm successfully updated'), 'Text "Preference peer_auth_realm successfully updated" appears');
    $d->find_element("Remote Authentication", 'link_text')->click();
    ok($d->wait_for_text('//table/tbody/tr/td[contains(text(), "peer_auth_realm")]/../td[4]', 'testpeering.com'), 'peer_auth_realm value has been set');

    diag("Go back to Servers/Rules");
    $d->get($server_rules_uri);

    diag('skip was here');
    diag("Delete mytestserver");
    $d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
    ok($d->find_element_by_css('#peering_servers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
    $d->fill_element('#peering_servers_table_filter input', 'css', $servername);
    ok($d->wait_for_text('//*[@id="peering_servers_table"]/tbody/tr/td[2]', $servername), "mytestserver was found");
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
    ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

    diag('Checking if Testing Group has been deleted');
    $d->fill_element('//*[@id="sip_peering_group_table_filter"]/label/input', 'xpath', $groupname);
    ok($d->find_element_by_css('#sip_peering_group_table tr > td.dataTables_empty', 'css'), 'Testing Group was deleted');
}

if(! caller) {
    ctr_peering();
    done_testing;
}

1;
