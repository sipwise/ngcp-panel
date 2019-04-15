use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag)];
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

$d->login_ok();

my $resellername = ("test" . int(rand(10000)));
my $contractid = ("test" . int(rand(10000)));
$c->create_reseller_contract($contractid);
$c->create_reseller($resellername, $contractid);

diag("Check if invalid reseller will be rejected");
$d->find_element('Create Reseller', 'link_text')->click();
$d->find_element('#save', 'css')->click();
ok($d->find_text("Contract field is required"), 'Error "Contract field is required" appears');
ok($d->find_text("Name field is required"), 'Error "Name field is required" appears');
$d->find_element('#mod_close', 'css')->click();

$c->create_reseller();

diag("Search nonexisting reseller");
my $searchfield = $d->find_element('#Resellers_table_filter label input', 'css');
$searchfield->send_keys('thisshouldnotexist');

diag("Verify that nothing is shown");
ok($d->find_element_by_css('#Resellers_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$searchfield->clear();
$searchfield->send_keys('active');
ok($d->wait_for_text('//*[@id="Resellers_table"]/tbody/tr[1]/td[2]', '1'), 'Default Reseller found');

diag("Click Edit on the first reseller shown (first row)");
sleep 1; #prevent a StaleElementReferenceException
my $row = $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]');
ok($row);
$d->move_action(element => $row);
my $btn = $d->find_child_element($row, './/a[contains(text(),"Edit")]');
ok($btn);
$btn->click();
#is($d->find_element("name", id)->get_attribute("value"), "reseller 1");
$d->find_element('#mod_close', 'css')->click();

diag("Click Terminate on the first reseller shown");
sleep 1; #prevent a StaleElementReferenceException
$row = $d->find_element('//*[@id="Resellers_table"]/tbody/tr[1]');
ok($row);
$d->move_action(element => $row,xoffset=>1); # 1 because if the mouse doesn't move, the buttons don't appear
$btn = $d->find_child_element($row, './/a[contains(@class,"btn-secondary")]');
ok($btn);
$btn->click();
ok($d->find_text("Are you sure?"), 'Delete dialog appears');
$d->find_element('//div[@id="dataConfirmModal"]//button[contains(text(),"Cancel")]')->click();

done_testing;
# vim: filetype=perl
