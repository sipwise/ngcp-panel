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
    version => '56.0',
    platform => 'linux',
    accept_ssl_certs => 1,
);

$d->login_ok();

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
$d->find_text('Create Peering Group'); # Should go back to prev form

$d->fill_element('#name', 'css', 'testinggroup');
$d->fill_element('#description', 'css', 'A group created for testing purposes');
$d->select_if_unselected('//table[@id="contractidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->find_element('#save', 'css')->click();
sleep 1;

diag("Edit Servers/Rules of testinggroup");
my $row = $d->find_element('(//table/tbody/tr/td[contains(text(), "testinggroup")]/..)[1]');
ok($row);
my $edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Details")]');
ok($edit_link);
$d->move_to(element => $row);
$d->general_action(type => 'pointer', id => 'mouse', actions => []); # in order to perform the "lazy move"
$edit_link->click();

diag("Create a Peering Rule");
$d->find_element('//a[contains(text(),"Create Outbound Peering Rule")]')->click();
$d->fill_element('#callee_prefix', 'css', '43');
$d->fill_element('#callee_pattern', 'css', '^sip');
$d->fill_element('#caller_pattern', 'css', '999');
$d->fill_element('#description', 'css', 'for testing purposes');
$d->find_element('#save', 'css')->click();

diag("Create a Peering Server");
$d->find_element('//a[contains(text(),"Create Peering Server")]')->click();
$d->fill_element('#name', 'css', 'mytestserver');
$d->fill_element('#ip', 'css', '10.0.0.100');
$d->fill_element('#host', 'css', 'sipwise.com');
$d->find_element('#save', 'css')->click();
$d->find_text('Peering server successfully created');

my $server_rules_uri = $d->get_current_url();

diag('Edit Preferences for "mytestserver".');
sleep 1; #make sure, we are on the right page
$d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#peering_servers_table tr > td.dataTables_empty', 'css');
$d->fill_element('#peering_servers_table_filter input', 'css', 'mytestserver');
$edit_link = $d->find_element('//table/tbody/tr/td[contains(text(), "mytestserver")]/../td//a[contains(text(),"Preferences")]');
$row = $d->find_element('//table/tbody/tr/td[contains(text(), "mytestserver")]/..');
ok($row);
ok($edit_link);
$d->move_to(element => $row);
$d->general_action(type => 'pointer', id => 'mouse', actions => []); # in order to perform the "lazy move"
$edit_link->click();

diag('Open the tab "Number Manipulations"');
$d->find_element("Number Manipulations", 'link_text')->click();

diag("Click edit for the preference inbound_upn");
$row = $d->find_element('//table/tbody/tr/td[normalize-space(text()) = "inbound_upn"]');
ok($row);
$edit_link = $d->find_child_element($row, '(./../td//a)[2]');
ok($edit_link);
$d->move_to(element => $row);
$d->general_action(type => 'pointer', id => 'mouse', actions => []); # in order to perform the "lazy move"
$edit_link->click();

diag('Change to "P-Asserted-Identity');
$d->find_element('//div[contains(@class,"modal-body")]//select[@id="inbound_upn"]/option[@value="pai_user"]')->click();
$d->find_element('#save', 'css')->click();
$d->find_text('Preference inbound_upn successfully updated');

diag("Go back to Servers/Rules");
$d->get($server_rules_uri);

my $delete_link;
diag('skip was here');
diag("Delete mytestserver");
sleep 1; #make sure, we are on the right page
$d->fill_element('#peering_servers_table_filter input', 'css', 'thisshouldnotexist');
$d->find_element('#peering_servers_table tr > td.dataTables_empty', 'css');
$d->fill_element('#peering_servers_table_filter input', 'css', 'mytestserver');
$row = $d->find_element('(//table/tbody/tr/td[contains(text(), "mytestserver")]/..)[1]');
ok($row);
$delete_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Delete")]');
ok($delete_link);
$d->move_to(element => $row);
$d->general_action(type => 'pointer', id => 'mouse', actions => []); # in order to perform the "lazy move"
$delete_link->click();
$d->find_text("Are you sure?");
$d->find_element('#dataConfirmOK', 'css')->click();
$d->find_text("successfully deleted"); # delete does not work

diag("Delete the previously created Peering Rule");
sleep 1;
$row = $d->find_element('//table[@id="PeeringRules_table"]/tbody/tr[1]');
ok($row);
$delete_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Delete")]');
ok($delete_link);
$d->move_to(element => $row);
$d->general_action(type => 'pointer', id => 'mouse', actions => []); # in order to perform the "lazy move"
$delete_link->click();
$d->find_text("Are you sure?");
$d->find_element('#dataConfirmOK', 'css')->click();

diag('skip was here');
ok($d->find_text("successfully deleted"));

diag('Go back to "SIP Peering Groups".');
$d->get($peerings_uri);

diag('Delete "testinggroup"');
$row = $d->find_element('(//table/tbody/tr/td[contains(text(), "testinggroup")]/..)[1]');
ok($row);
$delete_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Delete")]');
ok($delete_link);
$d->move_to(element => $row);
$d->general_action(type => 'pointer', id => 'mouse', actions => []); # in order to perform the "lazy move"
$delete_link->click();
$d->find_text("Are you sure?");
$d->find_element('#dataConfirmOK', 'css')->click();

diag('skip was here');
ok($d->find_text("successfully deleted"));

done_testing;
# vim: filetype=perl
