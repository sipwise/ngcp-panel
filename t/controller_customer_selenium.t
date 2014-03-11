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

my @chars = ("A".."Z", "a".."z");
my $rnd_id;
$rnd_id .= $chars[rand @chars] for 1..8;

$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Dashboard")]');

diag("Go to Customers page");
$d->findclick_ok(xpath => '//*[@id="main-nav"]//*[contains(text(),"Settings")]');
$d->findclick_ok(link_text => "Customers");

diag("Create a Customer");
$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Customers")]');
$d->findclick_ok(link_text => 'Create Customer');
$d->fill_element_ok([css => '#contactidtable_filter input', 'thisshouldnotexist']);
$d->find_ok(css => 'tr > td.dataTables_empty');
$d->fill_element_ok([css => '#contactidtable_filter input', 'default-customer']);
$d->select_if_unselected_ok(xpath => '//table[@id="contactidtable"]/tbody/tr[1]/td[contains(text(),"default-customer")]/..//input[@type="checkbox"]');
$d->fill_element_ok([css => '#billing_profileidtable_filter input', 'thisshouldnotexist']);
$d->find_ok(css => 'tr > td.dataTables_empty');
$d->fill_element_ok([css => '#billing_profileidtable_filter input', 'Default Billing Profile']);
$d->select_if_unselected_ok(xpath => '//table[@id="billing_profileidtable"]/tbody/tr[1]/td[contains(text(),"Default Billing Profile")]/..//input[@type="checkbox"]');
$d->fill_element_ok([id => 'external_id', $rnd_id]);
$d->findclick_ok(id => 'save');

diag("Open Details for our just created Customer");
sleep 2; #Else we might search on the previous page
$d->fill_element_ok([css => '#Customer_table_filter input', 'thisshouldnotexist']);
$d->find_ok(css => 'tr > td.dataTables_empty');
$d->fill_element_ok([css => '#Customer_table_filter input', $rnd_id]);
my $row = $d->find(xpath => '(//table/tbody/tr/td[contains(text(), "'.$rnd_id.'")]/..)[1]');
ok($row);
my $edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Details")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;

diag("Edit our contact");
$d->findclick_ok(xpath => '//div[contains(@class,"accordion-heading")]//a[contains(text(),"Contact Details")]');
$d->findclick_ok(xpath => '//div[contains(@class,"accordion-body")]//*[contains(@class,"btn-primary") and contains(text(),"Edit Contact")]');
$d->fill_element_ok([css => 'div.modal #firstname', "Alice"]);
$d->fill_element_ok([id => 'company', 'Sipwise']);
$d->findclick_ok(id => 'save');

diag("Check if successful");
$d->find_ok(xpath => '//div[contains(@class,"accordion-body")]//table//td[contains(text(),"Sipwise")]');

diag("Edit Fraud Limits");
$d->findclick_ok(xpath => '//div[contains(@class,"accordion-heading")]//a[contains(text(),"Fraud Limits")]');
sleep 2 if ($d->browser_name_in("phantomjs", "chrome", "firefox")); # time to move
$row = $d->find(xpath => '//div[contains(@class,"accordion-body")]//table//tr/td[contains(text(),"Monthly Settings")]');
ok($row);
$edit_link = $d->find_child_element($row, './../td//a[text()[contains(.,"Edit")]]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;

diag("Do Edit Fraud Limits");
$d->fill_element_ok([id => 'fraud_interval_limit', "100"]);
$d->fill_element_ok([id => 'fraud_interval_notify', 'mymail@example.org']);
$d->findclick_ok(id => 'save');
$d->find_ok(xpath => '//div[contains(@class,"accordion-body")]//table//td[contains(text(),"mymail@example.org")]');

diag("Terminate our customer");
$d->findclick_ok(xpath => '//a[contains(@class,"btn-primary") and text()[contains(.,"Back")]]');
$d->fill_element_ok([css => '#Customer_table_filter input', 'thisshouldnotexist']);
$d->find_ok(css => 'tr > td.dataTables_empty');
$d->fill_element_ok([css => '#Customer_table_filter input', $rnd_id]);
$row = $d->find(xpath => '(//table/tbody/tr/td[contains(text(), "'.$rnd_id.'")]/..)[1]');
ok($row);
$edit_link = $d->find_child_element($row, '(./td//a)[contains(text(),"Terminate")]');
ok($edit_link);
$d->move_to(element => $row);
$edit_link->click;
#sleep 2;
$d->findtext_ok("Are you sure?");
$d->findclick_ok(id => 'dataConfirmOK');
$d->findtext_ok("Customer successfully terminated");

done_testing;
# vim: filetype=perl
