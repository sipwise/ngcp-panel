use Sipwise::Base;
use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag)];
use Test::WebDriver::Sipwise qw();

my $browsername = $ENV{BROWSER_NAME} || "";
#possible values: htmlunit, chrome, firefox (default)
my $d = Test::WebDriver::Sipwise->new (browser_name => $browsername,
    'proxy' => {'proxyType' => 'system'});
$d->set_window_size(768,1024) if ($browsername ne "htmlunit");
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

diag("Go to reseller list");
$d->find_ok(xpath => '//*[@id="masthead"]//h2[contains(text(),"Dashboard")]');
$d->findclick_ok(xpath => '//a[@class="btn" and contains(@href,"/reseller")]');

diag("Search nonexisting reseller");
my $searchfield = $d->find(css => '#Resellers_table_filter label input');
ok($searchfield);
$searchfield->send_keys('donotfindme');

diag("Verify that nothing is shown");
my $elem = $d->find(css => '#Resellers_table td.dataTables_empty');
ok($elem);
is($elem->get_text,'No matching records found');

diag('Search for "1" in resellers');
$searchfield->clear();
$searchfield->send_keys('active');
$d->find_ok(css => '#Resellers_table tr.sw_action_row');
is($d->find(xpath => '//table[@id="Resellers_table"]//tr[1]/td[1]')->get_text,'1');

diag("Going to create a reseller");
$d->findclick_ok(link_text => 'Create Reseller');
$d->findclick_ok(id => 'save');
$d->findtext_ok("Contract field is required");
$d->findtext_ok("Name field is required");
$d->findclick_ok(id => 'mod_close');

diag("Click Edit on the first reseller shown (first row)");
sleep 2; #prevent a StaleElementReferenceException
my $row = $d->find(xpath => '//*[@id="Resellers_table"]/tbody/tr[1]');
ok($row);
$d->move_to(element => $row);
$d->find_ok(css => 'div.sw_actions.visible');
my $btn = $d->find_child_element($row, './/a[contains(text(),"Edit")]');
ok($btn);
$btn->click;
$d->findclick_ok(id => 'mod_close');

diag("Click Terminate on the first reseller shown");
sleep 2; #prevent a StaleElementReferenceException
$row = $d->find(xpath => '//*[@id="Resellers_table"]/tbody/tr[1]');
ok($row);
$d->move_to(element => $row);
$d->find_ok(css => 'div.sw_actions.visible');
$btn = $d->find_child_element($row, './/a[contains(@class,"btn-secondary")]');
ok($btn);
$btn->click;
$d->findtext_ok("Are you sure?");
$d->findclick_ok(xpath => '//div[@id="dataConfirmModal"]//button[contains(text(),"Cancel")]');

done_testing;
# vim: filetype=perl
