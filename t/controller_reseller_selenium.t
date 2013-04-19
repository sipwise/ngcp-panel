use Sipwise::Base;
use lib 't/lib';
use Test::More import => [qw(done_testing is ok)];
use Test::WebDriver::Sipwise qw();

#my $sel = Test::WWW::Selenium::Catalyst->start({default_names => 1});

my $d = Test::WebDriver::Sipwise->new;
$d->get_ok($ENV{CATALYST_SERVER} || 'http://localhost:3000');
$d->set_implicit_wait_timeout(1000);

#$sel->is_text_present_ok('Subscriber Sign In');

$d->findclick_ok(link_text => 'Admin');

#$sel->type_ok('username', 'administrator');
#$sel->type_ok('password', 'administrator');
$d->find(name => 'username')->send_keys('administrator');
$d->find(name => 'password')->send_keys('administrator');
$d->findclick_ok(name => 'submit');
#$sel->wait_for_page_to_load_ok(2000);

$d->text_is('//title', 'Dashboard');
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
is($d->find(css => '#Reseller_table tr:nth-of-type(1) > td:nth-of-type(1)')->get_text,'1');

#the rest is not yet ported to webdriver:

#$sel->type_ok($searchfield, '');
#$sel->type_keys_ok($searchfield, 'asdfasdfasdf');

#$sel->click_ok('//a[contains(text(),"Create Reseller")]');
#$sel->wait_for_page_to_load_ok(2000);
#$sel->click_ok('save');
#$sel->wait_for_page_to_load_ok(2000);
#$sel->click_ok('mod_close');
#$sel->wait_for_page_to_load_ok(2000);
#$sel->mouse_over_ok('css=#Reseller_table tr:nth-of-type(1)');
#$sel->click_ok('css=#Reseller_table tr:nth-of-type(1) a.btn-primary');
#$sel->wait_for_page_to_load_ok(2000);
#$sel->click_ok('mod_close');
#$sel->wait_for_page_to_load_ok(2000);
#$sel->mouse_over_ok('css=#Reseller_table tr:nth-of-type(1)');
#$sel->click_ok('css=#Reseller_table tr:nth-of-type(1) a.btn-secondary');
#$sel->wait_for_page_to_load_ok(2000);
#$sel->text_is('css=div.alert-info', 'Reseller delete not implemented!');

#$sel->debug();
#<STDIN>; # pause
done_testing;
# vim: filetype=perl
