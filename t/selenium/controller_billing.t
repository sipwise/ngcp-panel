use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;

my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome

my $d = Selenium::Remote::Driver::FirefoxExtensions->new(
    browser_name => $browsername,
    extra_capabilities => {
        acceptInsecureCerts => \1,
    },
);

my $c = Selenium::Collection::Common->new(
    driver => $d
);

my $billingname = ("billing" . int(rand(100000)) . "test");

$c->login_ok();

diag("Go to Billing page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element('//a[contains(@href,"/domain")]');
$d->find_element("Billing", 'link_text')->click();

diag("Create a billing profile");
$d->find_element('//*[@id="masthead"]//h2[contains(text(),"Billing Profiles")]')->click();
$d->find_element('Create Billing Profile', 'link_text')->click();
$d->find_element('//div[contains(@class,modal-body)]//table[@id="reselleridtable"]/tbody/tr[1]/td//input[@type="checkbox"]')->click();
$d->fill_element('#name', 'css', $billingname);
$d->fill_element('[name=handle]', 'css', $billingname);
$d->find_element('//select[@id="fraud_interval_lock"]/option[contains(text(),"foreign calls")]')->click();
$d->find_element('//div[contains(@class,"modal")]//input[@type="submit"]')->click();

diag('Search for Test Profile in billing profile');
$d->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');

diag("Open edit dialog for Test Profile");
$d->move_action(element => $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Edit")]'));
$d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Edit")]')->click();

diag("Edit Test Profile");
my $elem = $d->find_element('#name', 'css');
ok($elem);
$d->fill_element('#interval_charge', 'css', '3.2');
$d->find_element('#save', 'css')->click();
sleep 1;

diag('Open "Fees" for Test Profile');
$d->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
$d->move_action(element => $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Fees")]'));
$d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Fees")]')->click();

diag("Create a billing fee");
$d->find_element('Create Fee Entry', 'link_text')->click();
$d->find_element('//div[contains(@class,"modal")]//input[@value="Create Zone"]')->click();
diag("Create a billing zone (redirect from previous form)");
$d->fill_element('#zone', 'css', 'testingzone');
$d->fill_element('#detail', 'css', 'testingdetail');
$d->find_element('#save', 'css')->click();
diag("Back to orignial form (create billing fees)");
$d->select_if_unselected('//div[contains(@class,"modal")]//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..//input[@type="checkbox"]');
$d->fill_element('#source', 'css', '.*');
$d->fill_element('#destination', 'css', '.+');
$d->find_element('#save', 'css')->click();

diag("Delete billing fee");
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_fee_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="billing_fee_table_filter"]/label/input', 'xpath', '.+');
ok($d->wait_for_text('//*[@id="billing_fee_table"]/tbody/tr/td[3]', '.+'), 'Entry appears');
$d->move_action(element => $d->find_element('//*[@id="billing_fee_table"]/tbody/tr[1]/td//div//a[contains(text(), "Delete")]'));
$d->find_element('//*[@id="billing_fee_table"]/tbody/tr[1]/td//div//a[contains(text(), "Delete")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();
ok($d->find_text("successfully deleted"), 'Text "successfully deleted" appears');

diag("Click Edit Zones");
$d->find_element("Edit Zones", 'link_text')->click();
ok($d->find_element('//*[@id="masthead"]//h2[contains(text(),"Billing Zones")]'));

diag("Delete testingzone");
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_zone_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', 'testingdetail');
my $row = $d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..');
ok($row);
$d->move_action(element => $row);
$d->find_element('//div[contains(@class,"dataTables_wrapper")]//td[contains(text(),"testingzone")]/..//a[contains(text(),"Delete")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag("Go to Billing page (again)");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
ok($d->find_element('//a[contains(@href,"/domain")]'));
$d->find_element("Billing", 'link_text')->click();

diag('Open "Edit Peak Times" for Test Profile');
$d->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
$d->move_action(element => $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Off-Peaktimes")]'));
$d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Off-Peaktimes")]')->click();

diag("Wait for datatable loading");
my $dates_first_row_text;
do {
    sleep 1;
    diag("getting row");
    $dates_first_row_text = $d->find_element('//table[@id="date_definition_table"]/tbody/tr[1]/td[1]')->get_text();
    diag("Data table content: ".$dates_first_row_text);
} while ($dates_first_row_text =~ /Processing/i );

diag("Edit Wednesday");
$row = $d->find_element('//table//td[contains(text(),"Wednesday")]');
ok($row);
diag("Move mouse over 'Weekdays' row to make 'Edit' button available");
$d->move_action(element => ($d->find_element('//h3[contains(text(),"Weekdays")]')));
$d->move_action(element => $row);
diag("Find 'Edit' button for element 'Wednesday'");
sleep 1; # give ajax time to load
my $btn = $d->find_element('//table//td[contains(text(),"Wednesday")]/..//a[text()[contains(.,"Edit")]]');
ok($btn);
$btn->click();
ok($d->find_text("Edit Wednesday"), 'Edit Wednesday button exists');
diag("Pop-up 'Edit Wednesday' was properly opened");

diag("add/delete a time def to Wednesday");
$d->fill_element('#start', 'css', "03:14:15");
$d->fill_element('#end', 'css', "13:37:00");
$d->find_element('#add', 'css')->click();
$d->find_element('//div[contains(@class,"modal")]//i[@class="icon-trash"]/..')->click();

diag('skip was here');
$d->find_element('#mod_close', 'css')->click();

diag("Create a Date Definition");
$d->find_element('Create Special Off-Peak Date', 'link_text')->click();
$d->fill_element('#start', 'css', "2008-02-28 03:14:15");
$d->fill_element('#end', 'css', "2008-02-28 13:37:00");
$d->find_element('#save', 'css')->click();

diag("Find/delete my created date definition");
$d->scroll_to_element($d->find_element('//div[contains(@class, "dataTables_filter")]//input'));
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#date_definition_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//div[contains(@class, "dataTables_filter")]//input', 'xpath', '2008-02-28 03:14:15');
ok($d->wait_for_text('//*[@id="date_definition_table"]/tbody/tr/td[2]', '2008-02-28 03:14:15'), 'Created Date definition was found');
$d->move_action(element => ($d->find_element('//*[@id="date_definition_table"]/tbody//tr//td//div//a[contains(text(),"Delete")]')));
$d->find_element('//*[@id="date_definition_table"]/tbody//tr//td//div//a[contains(text(),"Delete")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag("Terminate our Billing Profile");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Billing", 'link_text')->click();
$d->fill_element('#billing_profile_table_filter label input', 'css', 'thisshouldnotexist');
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->wait_for_text('//*[@id="billing_profile_table"]/tbody/tr/td[2]', $billingname), 'Billing profile was found');
$d->move_action(element => $d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Terminate")]'));
$d->find_element('//*[@id="billing_profile_table"]/tbody/tr[1]//td//div//a[contains(text(), "Terminate")]')->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('#dataConfirmOK', 'css')->click();

diag("Check if Billing Profile has been removed");
$d->fill_element('#billing_profile_table_filter label input', 'css', $billingname);
ok($d->find_element_by_css('#billing_profile_table tr > td.dataTables_empty', 'css'), 'Billing Profile has been removed');

done_testing;