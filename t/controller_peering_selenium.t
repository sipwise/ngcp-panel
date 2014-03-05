use Sipwise::Base;
use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Test::WebDriver::Sipwise qw();

my $browsername = $ENV{BROWSER_NAME} || ""; #possible values: htmlunit, chrome
my $d = Test::WebDriver::Sipwise->new (browser_name => $browsername,
    'proxy' => {'proxyType' => 'system'});
$d->set_window_size(1024,1280) if ($browsername ne "htmlunit");
my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
$d->get_ok("$uri/logout"); #make sure we are logged out
$d->get_ok("$uri/login");
$d->set_implicit_wait_timeout(10000);

diag("Do Admin Login");
$d->find(link_text => 'Admin')->click;
$d->findtext_ok('Admin Sign In');
$d->find(name => 'username')->send_keys('administrator');
$d->find(name => 'password')->send_keys('administrator');
$d->findclick_ok(name => 'submit');

$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Dashboard")]');

diag("Go to Peerings page");
$d->findclick_ok(xpath => '//*[@id="main-nav"]//*[contains(text(),"Settings")]');
$d->findclick_ok(link_text => "Peerings");

diag("Create a Peering Group");
$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"SIP Peering Groups")]');
my $peerings_uri = $d->get_location;
$d->findclick_ok(link_text => 'Create Peering Group');

diag("Create a Peering Contract");
$d->findclick_ok(xpath => '//input[@type="button" and @value="Create Contract"]');
$d->select_if_unselected_ok(xpath => '//table[@id="contactidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->select_if_unselected_ok(xpath => '//table[@id="billing_profileidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->findclick_ok(xpath => '//div[contains(@class,"modal-body")]//div//select[@id="status"]/option[@value="active"]');
$d->findclick_ok(xpath => '//div[contains(@class,"modal")]//input[@type="submit"]');
$d->findtext_ok('Create Peering Group'); #Should go back to prev form

$d->fill_element_ok([id => 'name', 'testinggroup']);
$d->fill_element_ok([id => 'description', 'A group created for testing purposes']);
$d->select_if_unselected(xpath => '//table[@id="contractidtable"]/tbody/tr[1]//input[@type="checkbox"]');
$d->findclick_ok(id => 'save');

diag("Edit Servers/Rules of testinggroup");
my $row = $d->find(xpath => '(//table/tbody/tr/td[contains(text(), "testinggroup")]/..)[1]');
ok($row);
my $edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Details")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;

diag("Create a Peering Rule");
$d->findclick_ok(xpath => '//a[contains(text(),"Create Peering Rule")]');
$d->fill_element_ok(['id', 'callee_prefix', '43']);
$d->fill_element_ok(['id', 'callee_pattern', '^sip']);
$d->fill_element_ok(['id', 'caller_pattern', '999']);
$d->fill_element_ok(['id', 'description', 'for testing purposes']);
$d->findclick_ok(id => 'save');

diag("Create a Peering Server");
$d->findclick_ok(xpath => '//a[contains(text(),"Create Peering Server")]');
$d->fill_element_ok(['id', 'name', 'mytestserver']);
$d->fill_element_ok(['id', 'ip', '10.0.0.100']);
$d->fill_element_ok(['id', 'host', 'sipwise.com']);
$d->findclick_ok(id => 'save');
$d->findtext_ok('Peering server successfully created');

my $server_rules_uri = $d->get_location;

diag('Edit Preferences for "mytestserver".');
sleep 1; #make sure, we are on the right page
$row = $d->find(xpath => '(//table/tbody/tr/td[contains(text(), "mytestserver")]/..)[1]');
ok($row);
$edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Preferences")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;

diag('Open the tab "Number Manipulations"');
$d->findclick_ok(link_text => "Number Manipulations");

diag("Click edit for the preference inbound_upn");
$row = $d->find(xpath => '//table/tbody/tr/td[normalize-space(text()) = "inbound_upn"]');
ok($row);
$edit_link = $d->find_child_element($row, '(./../td//a)[2]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;

diag('Change to "P-Asserted-Identity');
$d->findclick_ok(xpath => '//div[contains(@class,"modal-body")]//select[@id="inbound_upn"]/option[@value="pai_user"]');
$d->findclick_ok(id => 'save');
$d->findtext_ok('Preference inbound_upn successfully updated');

diag("Go back to Servers/Rules");
$d->navigate_ok($server_rules_uri);

my $delete_link;
diag('skip was here');
diag("Delete mytestserver");
sleep 1; #make sure, we are on the right page
$row = $d->find(xpath => '(//table/tbody/tr/td[contains(text(), "mytestserver")]/..)[1]');
ok($row);
$delete_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Delete")]');
ok($delete_link);
$d->move_to(element => $row);
$delete_link->click;
$d->findtext_ok("Are you sure?");
$d->findclick_ok(id => 'dataConfirmOK');
$d->findtext_ok("successfully deleted"); # delete does not work

diag("Delete the previously created Peering Rule");
sleep 1;
$row = $d->find(xpath => '//table[@id="PeeringRules_table"]/tbody/tr[1]');
ok($row);
$delete_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Delete")]');
ok($delete_link);
$d->move_to(element => $row);
$delete_link->click;
$d->findtext_ok("Are you sure?");
$d->findclick_ok(id => 'dataConfirmOK');

diag('skip was here');
$d->findtext_ok("successfully deleted");

diag('Go back to "SIP Peering Groups".');
$d->navigate_ok($peerings_uri);

diag('Delete "testinggroup"');
$row = $d->find(xpath => '(//table/tbody/tr/td[contains(text(), "testinggroup")]/..)[1]');
ok($row);
$delete_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Delete")]');
ok($delete_link);
$d->move_to(element => $row);
$delete_link->click;
$d->findtext_ok("Are you sure?");
$d->findclick_ok(id => 'dataConfirmOK');

diag('skip was here');
$d->findtext_ok("successfully deleted");

done_testing;
# vim: filetype=perl
