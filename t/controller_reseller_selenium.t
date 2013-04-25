use Sipwise::Base;
use lib 't/lib';
use Test::More import => [qw(done_testing is ok)];
use Test::WebDriver::Sipwise qw();

#my $sel = Test::WWW::Selenium::Catalyst->start({default_names => 1});

my $browsername = $ENV{BROWSER_NAME} || ""; #possible values: htmlunit, chrome
my $d = Test::WebDriver::Sipwise->new (browser_name => $browsername,
    'proxy' => {'proxyType' => 'system'});
$d->set_window_size(800,1280) if ($browsername ne "htmlunit");
my $uri = $ENV{CATALYST_SERVER} || 'http://localhost:3000';
$d->get_ok("$uri/logout"); #make sure we are logged out
$d->get_ok("$uri/login");
$d->set_implicit_wait_timeout(1000);

#$sel->is_text_present_ok('Subscriber Sign In');

$d->findclick_ok(link_text => 'Admin');

#$sel->type_ok('username', 'administrator');
#$sel->type_ok('password', 'administrator');
$d->find(name => 'username')->send_keys('administrator');
$d->find(name => 'password')->send_keys('administrator');
$d->findclick_ok(name => 'submit');
#$sel->wait_for_page_to_load_ok(2000);

#$d->text_is('//title', 'Dashboard');
$d->title_is('Dashboard');
$d->findclick_ok(xpath => '//a[@class="btn" and @href="/reseller"]');

my $searchfield = $d->find(css => '#Reseller_table_filter label input');
ok($searchfield);
$searchfield->send_keys('donotfindme');

my $elem = $d->find(css => '#Reseller_table td.dataTables_empty');
ok($elem);
is($elem->get_text,'No matching records found');

$searchfield->clear();
$searchfield->send_keys('1');
$d->find_ok(css => '#Reseller_table tr.sw_action_row');
is($d->find(xpath => '//table[@id="Reseller_table"]//tr[1]/td[1]')->get_text,'1');

$d->findclick_ok(link_text => 'Create Reseller');
$d->findclick_ok(id => 'save');
$d->findtext_ok("Contract field is required");
$d->findtext_ok("Name field is required");
$d->findtext_ok("Status field is required");
$d->findclick_ok(id => 'mod_close');

sleep 1; #prevent a StaleElementReferenceException
my $row = $d->find(xpath => '//*[@id="Reseller_table"]/tbody/tr[1]');
ok($row);
$d->move_to(element => $row);
my $btn = $d->find_child_element($row, './/a[contains(text(),"Edit")]');
ok($btn);
$btn->click;
is($d->find(id => "name")->get_attribute("value"), "reseller 1");
$d->findclick_ok(id => 'mod_close');

sleep 1; #prevent a StaleElementReferenceException
$row = $d->find(xpath => '//*[@id="Reseller_table"]/tbody/tr[1]');
ok($row);
$d->move_to(element => $row);
$btn = $d->find_child_element($row, './/a[contains(@class,"btn-secondary")]');
ok($btn);
$btn->click;
$d->findtext_ok("Are you sure?");
$d->findclick_ok(xpath => '//div[@id="dataConfirmModal"]//a[contains(text(),"Delete")]');
is($d->find(css => 'div.alert-info')->get_text, 'Reseller delete not implemented!');

done_testing;
# vim: filetype=perl
