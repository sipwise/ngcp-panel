use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag todo_skip)];
use Selenium::Remote::Driver::Extensions qw();

diag("Init");
my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
my $browsername = $ENV{BROWSER_NAME} || "firefox"; # possible values: firefox, htmlunit, chrome
my $d = Selenium::Remote::Driver::Extensions->new (
    'browser_name' => $browsername,
    'proxy' => {'proxyType' => 'system'} );

diag("Loading login page (logout first)");
$d->set_window_size(1024,1280) if ($browsername ne "htmlunit");
$d->get("$uri/logout"); # make sure we are logged out
$d->get("$uri/login");
$d->set_implicit_wait_timeout(10000);
$d->default_finder('xpath');

diag("Do Admin Login");
$d->find_text("Admin Sign In");
is($d->get_title, '');
$d->find_element('username', name)->send_keys('administrator');
$d->find_element('password', name)->send_keys('administrator');
$d->find_element('submit', name)->click();
is($d->find_element('//*[@id="masthead"]//h2')->get_text(), "Dashboard");

my @chars = ("A".."Z", "a".."z");
my $rnd_id;
$rnd_id .= $chars[rand @chars] for 1..8;

diag("Go to Customers page");
$d->find_element('//*[@id="main-nav"]//*[contains(text(),"Settings")]')->click();
$d->find_element("Customers", link_text)->click();

diag("Create a Customer");
$d->find_element('//*[@id="masthead"]//h2[contains(text(),"Customers")]');
$d->find_element('Create Customer', link_text)->click();
$d->fill_element('#contactidtable_filter input', css, 'thisshouldnotexist');
$d->find_element('#contactidtable tr > td.dataTables_empty', css);
$d->fill_element('#contactidtable_filter input', css, 'default-customer');
$d->select_if_unselected('//table[@id="contactidtable"]/tbody/tr[1]/td[contains(text(),"default-customer")]/..//input[@type="checkbox"]');
$d->fill_element('#billing_profileidtable_filter input', css, 'thisshouldnotexist');
$d->find_element('#billing_profileidtable tr > td.dataTables_empty', css);
$d->fill_element('#billing_profileidtable_filter input', css, 'Default Billing Profile');
$d->select_if_unselected('//table[@id="billing_profileidtable"]/tbody/tr[1]/td[contains(text(),"Default Billing Profile")]/..//input[@type="checkbox"]');
eval { #lets only try this
    $d->select_if_unselected('//table[@id="productidtable"]/tbody/tr[1]/td[contains(text(),"Basic SIP Account")]/..//input[@type="checkbox"]');
};
$d->fill_element('external_id', id, $rnd_id);
$d->find_element('save', id)->click();

diag("Open Details for our just created Customer");
sleep 2; #Else we might search on the previous page
$d->fill_element('#Customer_table_filter input', css, 'thisshouldnotexist');
$d->find_element('#Customer_table tr > td.dataTables_empty', css);
$d->fill_element('#Customer_table_filter input', css, $rnd_id);
my $row = $d->find_element('(//table/tbody/tr/td[contains(text(), "'.$rnd_id.'")]/..)[1]');
ok($row);
my $edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Details")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click();

diag("Edit our contact");
$d->find_element('//div[contains(@class,"accordion-heading")]//a[contains(text(),"Contact Details")]')->click();
$d->find_element('//div[contains(@class,"accordion-body")]//*[contains(@class,"btn-primary") and contains(text(),"Edit Contact")]')->click();
$d->fill_element('div.modal #firstname', css, "Alice");
$d->fill_element('company', id, 'Sipwise');
# Choosing Country:
$d->fill_element('#countryidtable_filter input', css, 'thisshouldnotexist');
$d->find_element('#countryidtable tr > td.dataTables_empty', css);
$d->fill_element('#countryidtable_filter input', css, 'Ukraine');
$d->select_if_unselected('//table[@id="countryidtable"]/tbody/tr[1]/td[contains(text(),"Ukraine")]/..//input[@type="checkbox"]');
# Save
$d->find_element('save', id)->click();

diag("Check if successful");
$d->find_element('//div[contains(@class,"accordion-body")]//table//td[contains(text(),"Sipwise")]');

diag("Edit Fraud Limits");
$d->find_element('//div[contains(@class,"accordion-heading")]//a[contains(text(),"Fraud Limits")]')->click();
sleep 2 if ($d->browser_name_in("phantomjs", "chrome", "firefox")); # time to move
$row = $d->find_element('//div[contains(@class,"accordion-body")]//table//tr/td[contains(text(),"Monthly Settings")]');
ok($row);
$edit_link = $d->find_child_element($row, './../td//a[text()[contains(.,"Edit")]]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click();

diag("Do Edit Fraud Limits");
$d->fill_element('fraud_interval_limit', id, "100");
$d->fill_element('fraud_interval_notify', id, 'mymail@example.org');
$d->find_element('save', id)->click();
$d->find_element('//div[contains(@class,"accordion-body")]//table//td[contains(text(),"mymail@example.org")]');

diag("Terminate our customer");
$d->find_element('//a[contains(@class,"btn-primary") and text()[contains(.,"Back")]]')->click();
$d->fill_element('#Customer_table_filter input', css, 'thisshouldnotexist');
$d->find_element('#Customer_table tr > td.dataTables_empty', css);
$d->fill_element('#Customer_table_filter input', css, $rnd_id);
$row = $d->find_element('(//table/tbody/tr/td[contains(text(), "'.$rnd_id.'")]/..)[1]');
ok($row);
$edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Terminate")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click();
#sleep 2;
$d->find_text("Are you sure?");
$d->find_element('dataConfirmOK', id)->click();
$d->find_text("Customer successfully terminated");

done_testing;
# vim: filetype=perl
