use warnings;
use strict;

use lib 't/lib';
use Test::More import => [qw(done_testing is ok diag like)];
use Selenium::Remote::Driver::FirefoxExtensions;
use Selenium::Collection::Common;
use Selenium::Collection::Functions;

my ($port) = @_;
my $d = Selenium::Collection::Functions::create_driver($port);
my $c = Selenium::Collection::Common->new(
    driver => $d
);

my $domainstring = ("domain" . int(rand(100000)) . ".example.org");
my $run_ok = 0;

$c->login_ok();
$c->create_domain($domainstring);

diag('Try to add a empty domain');
$d->find_element('Create Domain', 'link_text')->click();
$d->find_element('//*[@id="save"]')->click();

diag('Check error messages');
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Reseller field is required")]'));
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "SIP Domain field is required")]'));
$d->find_element('//*[@id="mod_close"]')->click();

diag("Check if entry exists and if the search works");
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', 'thisshouldnotexist');
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Garbage text was not found');
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);

diag("Check domain details");
ok($d->find_element_by_xpath('//*[@id="Domain_table"]/tbody/tr[1]/td[contains(text(), "default")]'), "Reseller is correct");
ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[contains(text(), "domain")]', $domainstring), "Domain name is correct");

diag("Open Preferences of first Domain");
$d->move_and_click('//*[@id="Domain_table"]//tr[1]//td//a[contains(text(), "Preferences")]', 'xpath', '//*[@id="Domain_table_filter"]/label/input');

diag("Go to 'Acces Restrictions'");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element("Access Restrictions", 'link_text'));

diag("Click edit for the preference concurrent_max");
$d->move_and_click('//table//tr/td[contains(text(), "concurrent_max")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "reject_emergency")]');

diag("Try to change this to a value which is not a number");
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");
$d->fill_element('#concurrent_max', 'css', 'thisisnonumber');
$d->find_element("#save", 'css')->click();

diag("Check error message");
ok($d->find_element_by_xpath('//form//div//span[contains(text(), "Value must be an integer")]'));

diag('Type 789 and click Save');
$d->fill_element('#concurrent_max', 'css', '789');
$d->find_element('#save', 'css')->click();

diag('Check if value has been applied');
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference concurrent_max successfully updated",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element("Access Restrictions", 'link_text'));
ok($d->find_element_by_xpath('//table/tbody/tr/td[contains(text(), "concurrent_max")]/../td[contains(text(), "789")]'), "Value has been applied");

diag("Click edit for the preference allowed_ips");
$d->move_and_click('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td/div/a[contains(text(), "Edit")]', 'xpath', '//table/tbody/tr/td[contains(text(), "man_allowed_ips")]/../td/div/a[contains(text(), "Edit")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");

diag("Enter an IP address");
$d->find_element('//*[@id="add"]')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//div//span[contains(text(), "Invalid IPv4 or IPv6 address")]'), "Invalid IP address detected");
$d->fill_element('//*[@id="allowed_ips"]', 'xpath', '127.0.0.0.0');
$d->find_element('//*[@id="add"]')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//div//span[contains(text(), "Invalid IPv4 or IPv6 address")]'), "Invalid IP address detected");
$d->fill_element('//*[@id="allowed_ips"]', 'xpath', 'thisisnonumber');
$d->find_element('//*[@id="add"]')->click();
ok($d->find_element_by_xpath('//*[@id="mod_edit"]//div//span[contains(text(), "Invalid IPv4 or IPv6 address")]'), "Invalid IP address detected");
$d->fill_element('//*[@id="allowed_ips"]', 'xpath', '127.0.0.1');
$d->find_element('//*[@id="add"]')->click();
$d->find_element('//*[@id="mod_close"]')->click();

diag("Check if IP address has been added");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element("Access Restrictions", 'link_text'));
ok($d->find_element_by_xpath('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td[contains(text(), "127.0.0.1")]'), "IP address has beeen found");

diag("Add another IP address");
$d->move_and_click('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td/div/a[contains(text(), "Edit")]', 'xpath', '//table/tbody/tr/td[contains(text(), "man_allowed_ips")]/../td/div/a[contains(text(), "Edit")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");
$d->fill_element('//*[@id="allowed_ips"]', 'xpath', '10.0.0.138');
$d->find_element('//*[@id="add"]')->click();
$d->find_element('//*[@id="mod_close"]')->click();

diag("Check if IP address has been added");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element("Access Restrictions", 'link_text'));
ok($d->find_element_by_xpath('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td[contains(text(), "10.0.0.138")]'), "IP address has beeen found");

diag("Delete the first IP address");
$d->move_and_click('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td/div/a[contains(text(), "Edit")]', 'xpath', '//table/tbody/tr/td[contains(text(), "man_allowed_ips")]/../td/div/a[contains(text(), "Edit")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");
$d->find_element('//*[@id="mod_edit"]/div[2]/div[2]/a')->click();
$d->find_element('//*[@id="mod_close"]')->click();

diag("Check if IP addresses have been changed");
$d->find_element('//*[@id="toggle-accordions"]')->click();
$d->scroll_to_element($d->find_element("Access Restrictions", 'link_text'));
ok($d->find_element_by_xpath('//table/tbody/tr/td[contains(text(), "allowed_ips")]/../td[contains(text(), "10.0.0.138")]'), "IP address has beeen found");

diag("Enable Opus Mono");
$d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "transcode_opus_mono")]'));
$d->move_and_click('//table//tr/td[contains(text(), "transcode_opus_mono")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "transcode_opus_stereo")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");
$d->select_if_unselected('//*[@id="transcode_opus_mono"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check if Opus Mono was enabled");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference transcode_opus_mono successfully updated",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "transcode_opus_mono")]/../td//input[@checked="checked"]'), "Opus mono was enabled");

diag("Change Opus Mono Bitrate");
$d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "transcode_opus_mono")]'));
$d->move_and_click('//table//tr/td[contains(text(), "opus_mono_bitrate")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "opus_stereo_bitrate")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");

diag("Change to 32 kbit/s");
$d->find_element('//*[@id="opus_mono_bitrate"]')->click();
$d->find_element('//*[@id="opus_mono_bitrate"]/option[contains(text(), "32")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Bitrate was applied");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference opus_mono_bitrate successfully updated",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "opus_mono_bitrate")]/../td/select/option[text()[contains(., "32")]][@selected="selected"]'), "Correct bitrate was selected");

diag("Enable Opus Stereo");
$d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "transcode_opus_stereo")]'));
$d->move_and_click('//table//tr/td[contains(text(), "transcode_opus_stereo")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "transcode_opus_mono")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");
$d->select_if_unselected('//*[@id="transcode_opus_stereo"]');
$d->find_element('//*[@id="save"]')->click();

diag("Check if Opus Stereo was enabled");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference transcode_opus_stereo successfully updated",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "transcode_opus_stereo")]/../td//input[@checked="checked"]'), "Opus stereo was enabled");

diag("Change Opus Stereo Bitrate");
$d->scroll_to_element($d->find_element('//table//tr/td[contains(text(), "transcode_opus_stereo")]'));
$d->move_and_click('//table//tr/td[contains(text(), "opus_stereo_bitrate")]/../td//a[contains(text(), "Edit")]', 'xpath', '//table//tr/td[contains(text(), "opus_mono_bitrate")]');
ok($d->find_element_by_xpath('//*[@id="mod_edit"]/div/h3[contains(text(), "Edit Preference")]'), "Edit Window has been opened");

diag("Change to 32 kbit/s");
$d->find_element('//*[@id="opus_stereo_bitrate"]')->click();
$d->find_element('//*[@id="opus_stereo_bitrate"]/option[contains(text(), "32")]')->click();
$d->find_element('//*[@id="save"]')->click();

diag("Check if Bitrate was applied");
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Preference opus_stereo_bitrate successfully updated",  "Correct Alert was shown");
$d->find_element('//*[@id="toggle-accordions"]')->click();
ok($d->find_element_by_xpath('//table//tr/td[contains(text(), "opus_stereo_bitrate")]/../td/select/option[text()[contains(., "32")]][@selected="selected"]'), "Correct bitrate was selected");

diag("Open delete dialog and press cancel");
$c->delete_domain($domainstring, 1);
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
ok($d->wait_for_text('//*[@id="Domain_table"]/tbody/tr[1]/td[3]', $domainstring), 'Domain is still here');

diag('Open delete dialog and press delete');
$c->delete_domain($domainstring, 0);
$d->fill_element('//*[@id="Domain_table_filter"]/label/input', 'xpath', $domainstring);
is($d->get_text_safe('//*[@id="content"]//div[contains(@class, "alert")]'), "Domain successfully deleted!",  "Correct Alert was shown");
ok($d->find_element_by_css('#Domain_table tr > td.dataTables_empty', 'css'), 'Domain was deleted');

diag("This test run was successfull");
$run_ok = 1;

END {
    if(!$run_ok) {
        $c->crash_handler("/results/crash_domain.png");
    }
    $d->quit();
    done_testing;
}