use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::Extensions qw();

diag("Init");
my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
my $d = Selenium::Remote::Driver::Extensions->new (
    'browser_name' => $browsername,
    'proxy' => {'proxyType' => 'system'} );

$d->login_ok();

diag("Go to Billing page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('//a[contains(@href,"/domain")]');
$d->find_element("Billing", 'link_text')->click();

diag("Create a billing profile");
$d->find_element('//*[@id="masthead"]//h2[contains(text(),"Billing Profiles")]')->click();
$d->find_element('Create Billing Profile', 'link_text')->click();
$d->find_element('name', 'id')->send_keys('mytestprofile');
$d->fill_element('handle', 'name', 'mytestprofile');
$d->find_element('fraud_interval_lock', 'id');
$d->find_element('//select[@id="fraud_interval_lock"]/option[contains(text(),"foreign calls")]')->click();
$d->find_element('//div[contains(@class,modal-body)]//table[@id="reselleridtable"]/tbody/tr[1]/td//input[@type="checkbox"]')->click();
$d->find_element('//div[contains(@class,"modal")]//input[@type="submit"]')->click();

diag("Search nonexisting billing profile");
my $searchfield = $d->find_element('#billing_profile_table_filter label input', 'css');
ok($searchfield);
$searchfield->send_keys('donotfindme');

diag("Verify that nothing is shown");
my $elem = $d->find_element('#billing_profile_table td.dataTables_empty', 'css');
ok($elem);
is($elem->get_text, 'No matching records found');

diag('Search for "mytestprofile" in billing profile');
$searchfield->clear();
$searchfield->send_keys('mytestprofile');
#sleep 1;
#$d->find_element('#billing_profile_table tr.sw_action_row', css);
ok($d->find_element('//table[@id="billing_profile_table"]//tr[1]/td[2][contains(text(),"mytestprofile")]'));

diag("Open edit dialog for mytestprofile");
my $row = $d->find_element('//table/tbody/tr/td[contains(text(), "mytestprofile")]/..');
ok($row);
my $edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Edit")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click();

diag("Edit mytestprofile");
$elem = $d->find_element('name', 'id');
ok($elem);
is($elem->get_value, "mytestprofile");
$d->fill_element('interval_charge', 'id', '3.2');
$d->find_element('save', 'id')->click();

diag('Open "Fees" for mytestprofile');
$row = $d->find_element('//table/tbody/tr/td[contains(text(), "mytestprofile")]/..');
ok($row);
$edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Fees")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click();
$d->find_element('//*[@id="masthead"]//h2[contains(text(),"Billing Fees")]');

diag("Create a billing fee");
$d->find_element('Create Fee Entry', 'link_text')->click();
$d->find_element('//div[contains(@class,"modal")]//input[@value="Create Zone"]')->click();
diag("Create a billing zone (redirect from previous form)");
$d->fill_element('zone', 'name', 'testingzone');
$d->fill_element('detail', 'name', 'testingdetail');
$d->find_element('save', 'name')->click();
diag("Back to orignial form (create billing fees)");
#sleep 2; # give ajax time to load
$d->select_if_unselected('//div[contains(@class,"modal")]//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..//input[@type="checkbox"]');
$d->fill_element('source', 'id', '.*');
$d->fill_element('destination', 'name', '.+');
$d->find_element('save', 'id')->click();

diag("Delete billing fee");
$d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingdetail")]/..//a[contains(@class,"btn-primary") and contains(text(),"Edit")]');
$row = $d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingdetail")]/..');
ok($row, "Find row");
$d->move_to(element => $row);
ok(1, "Mouse over row");
$d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingdetail")]/..//a[contains(@class,"btn-secondary") and contains(text(),"Delete")]')->click();
ok($d->find_text("Are you sure?"));
$d->find_element('dataConfirmOK', 'id')->click();
diag('skip was here');
ok($d->find_text("successfully deleted"));

diag("Click Edit Zones");
$d->find_element("Edit Zones", 'link_text')->click();
ok($d->find_element('//*[@id="masthead"]//h2[contains(text(),"Billing Zones")]'));

diag("Delete testingzone");
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', 'thisshouldnotexist');
$d->find_element('#billing_zone_table tr > td.dataTables_empty', 'css');
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', 'testingdetail');
$row = $d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..');
ok($row);
$d->move_to(element => $row);
$d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..//a[contains(text(),"Delete")]')->click();
$d->find_text("Are you sure?");
$d->find_element('dataConfirmOK', 'id')->click();

diag("Go to Billing page (again)");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
ok($d->find_element('//a[contains(@href,"/domain")]'));
$d->find_element("Billing", 'link_text')->click();

diag('Open "Edit Peak Times" for mytestprofile');
$row = $d->find_element('//table/tbody/tr/td[contains(text(), "mytestprofile")]/..');
ok($row);
$edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Peaktimes")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click();
ok($d->find_element('//*[@id="masthead"]//h2[contains(text(),"times for mytestprofile")]'));

diag("Edit Wednesday");
$row = $d->find_element('//table//td[contains(text(),"Wednesday")]');
ok($row);
$d->move_to(element => ($d->find_element('//h3[contains(text(),"Weekdays")]')));
sleep 2 if ($d->browser_name_in("firefox", "htmlunit"));
$d->move_to(element => $row);
$d->find_element('//table//td[contains(text(),"Wednesday")]/..//a[text()[contains(.,"Edit")]]')->click();
$d->find_text("Edit Wednesday");

diag("add/delete a time def to Wednesday");
$d->fill_element('start', 'name', "03:14:15");
$d->fill_element('end', 'name', "13:37:00");
$d->find_element('add', 'name')->click();
$d->find_element('//div[contains(@class,"modal")]//i[@class="icon-trash"]/..')->click();

diag('skip was here');
$d->find_element('mod_close', 'id')->click();

diag("Create a Date Definition");
$d->find_element('Create Special Off-Peak Date', 'link_text')->click();
$d->fill_element('start', 'name', "2008-02-28 03:14:15");
$d->fill_element('end', 'name', "2008-02-28 13:37:00");
$d->find_element('save', 'name')->click();

diag("Find/delete my created date definition");
$row = $d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"2008-02-28")]/..');
ok($row);
$d->move_to(element => $row);
$edit_link = $d->find_child_element($row, './/a[contains(@class,"btn-secondary")]');
ok($edit_link);
sleep 2 if ($browsername eq "htmlunit");
$edit_link->click();
$d->find_text("Are you sure?");
$d->find_element('dataConfirmOK', 'id')->click();

done_testing;
# vim: filetype=perl
