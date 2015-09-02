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
$d->findtext_ok('Admin Sign In');
$d->find(name => 'username')->send_keys('administrator');
$d->find(name => 'password')->send_keys('administrator');
$d->findclick_ok(name => 'submit');

$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Dashboard")]');

diag("Go to Billing page");
$d->findclick_ok(xpath => '//*[@id="main-nav"]//*[contains(text(),"Settings")]');
$d->find_ok(xpath => '//a[contains(@href,"/domain")]');
$d->findclick_ok(link_text => "Billing");

diag("Create a billing profile");
$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Billing Profiles")]');
$d->findclick_ok(link_text => 'Create Billing Profile');
$d->find(id => 'name')->send_keys('mytestprofile');
$d->fill_element_ok(['name', 'handle', 'mytestprofile']);
$d->find_ok(id => 'fraud_interval_lock');
$d->findclick_ok(xpath => '//select[@id="fraud_interval_lock"]/option[contains(text(),"foreign calls")]');
$d->findclick_ok(xpath => '//div[contains(@class,modal-body)]//table[@id="reselleridtable"]/tbody/tr[1]/td//input[@type="checkbox"]');

$d->findclick_ok(xpath => '//div[contains(@class,"modal")]//input[@type="submit"]');

diag("Search nonexisting billing profile");
my $searchfield = $d->find(css => '#billing_profile_table_filter label input');
ok($searchfield);
$searchfield->send_keys('donotfindme');

diag("Verify that nothing is shown");
my $elem = $d->find(css => '#billing_profile_table td.dataTables_empty');
ok($elem);
is($elem->get_text,'No matching records found');

diag('Search for "mytestprofile" in billing profile');
$searchfield->clear();
$searchfield->send_keys('mytestprofile');
$d->find_ok(css => '#billing_profile_table tr.sw_action_row');
is($d->find(xpath => '//table[@id="billing_profile_table"]//tr[1]/td[2]')->get_text,'mytestprofile');

diag("Open edit dialog for mytestprofile");
my $row = $d->find(xpath => '//table/tbody/tr/td[contains(text(), "mytestprofile")]/..');
ok($row);
my $edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Edit")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;

diag("Edit mytestprofile");
$elem = $d->find(id => 'name');
ok($elem);
is($elem->get_value, "mytestprofile");
$d->fill_element_ok(['id', 'interval_charge', '3.2']);
$d->findclick_ok(id => 'save');

diag('Open "Fees" for mytestprofile');
$row = $d->find(xpath => '//table/tbody/tr/td[contains(text(), "mytestprofile")]/..');
ok($row);
$edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Fees")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;
$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Billing Fees")]');

diag("Create a billing fee");
$d->findclick_ok(link_text => 'Create Fee Entry');
$d->findclick_ok(xpath => '//div[contains(@class,"modal")]//input[@value="Create Zone"]');
diag("Create a billing zone (redirect from previous form)");
$d->fill_element_ok([name => 'zone', 'testingzone']);
$d->fill_element_ok([name => 'detail', 'testingdetail']);
$d->findclick_ok(name => 'save');
diag("Back to orignial form (create billing fees)");
#sleep 2; # give ajax time to load
$d->select_if_unselected_ok(xpath => '//div[contains(@class,"modal")]//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..//input[@type="checkbox"]');
$d->fill_element_ok([id => 'source', '.*']);
$d->fill_element_ok([name => 'destination', '.+']);
$d->findclick_ok(id => 'save');

diag("Delete billing fee");
$d->find_ok(xpath => '//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingdetail")]/..//a[contains(@class,"btn-primary") and contains(text(),"Edit")]');
$row = $d->find(xpath => '//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingdetail")]/..');
ok($row);
$d->move_to(element => $row);
$d->findclick_ok(xpath => '//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingdetail")]/..//a[contains(@class,"btn-secondary") and contains(text(),"Delete")]');
$d->findtext_ok("Are you sure?");
$d->findclick_ok(id => 'dataConfirmOK');
diag('skip was here');
$d->findtext_ok("successfully deleted");

diag("Click Edit Zones");
$d->findclick_ok(link_text => "Edit Zones");
$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Billing Zones")]');

diag("Delete testingzone");
$d->fill_element_ok([xpath => '//div[contains(@class, "dataTables_filter")]//input', 'thisshouldnotexist']);
$d->find_ok(css => '#billing_zone_table tr > td.dataTables_empty');
$d->fill_element_ok([xpath => '//div[contains(@class, "dataTables_filter")]//input', 'testingdetail']);
$row = $d->find(xpath => '//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..');
ok($row);
$d->move_to(element => $row);
$d->findclick_ok(xpath => '//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..//a[contains(text(),"Delete")]');
$d->findtext_ok("Are you sure?");
$d->findclick_ok(id => 'dataConfirmOK');

diag("Go to Billing page (again)");
$d->findclick_ok(xpath => '//*[@id="main-nav"]//*[contains(text(),"Settings")]');
$d->find_ok(xpath => '//a[contains(@href,"/domain")]');
$d->findclick_ok(link_text => "Billing");

diag('Open "Edit Peak Times" for mytestprofile');
$row = $d->find(xpath => '//table/tbody/tr/td[contains(text(), "mytestprofile")]/..');
ok($row);
$edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Peaktimes")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;
$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"times for mytestprofile")]');

diag("Edit Wednesday");
$row = $d->find(xpath => '//table//td[contains(text(),"Wednesday")]');
ok($row);
$d->move_to(element => ($d->find(xpath => '//h3[contains(text(),"Weekdays")]')));
sleep 2 if ($d->browser_name_in("firefox", "htmlunit"));
$d->move_to(element => $row);
$d->findclick_ok(xpath => '//table//td[contains(text(),"Wednesday")]/..//a[text()[contains(.,"Edit")]]');
$d->findtext_ok("Edit Wednesday");

diag("add/delete a time def to Wednesday");
$d->fill_element_ok([name => 'start', "03:14:15"]);
$d->fill_element_ok([name => 'end', "13:37:00"]);
$d->findclick_ok(name => 'add');
$d->findclick_ok(xpath => '//div[contains(@class,"modal")]//i[@class="icon-trash"]/..');

diag('skip was here');
$d->findclick_ok(id => 'mod_close');

diag("Create a Date Definition");
$d->findclick_ok(link_text => 'Create Special Off-Peak Date');
$d->fill_element_ok([name => 'start', "2008-02-28 03:14:15"]);
$d->fill_element_ok([name => 'end', "2008-02-28 13:37:00"]);
$d->findclick_ok(name => 'save');

diag("Find/delete my created date definition");
$row = $d->find(xpath => '//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"2008-02-28")]/..');
ok($row);
$d->move_to(element => $row);
$edit_link = $d->find_child_element($row, './/a[contains(@class,"btn-secondary")]');
ok($edit_link);
sleep 2 if ($browsername eq "htmlunit");
$edit_link->click;
$d->findtext_ok("Are you sure?");
$d->findclick_ok(id => 'dataConfirmOK');

done_testing;
# vim: filetype=perl
